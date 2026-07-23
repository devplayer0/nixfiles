# Networking

This page describes how addressing works across the boxes: the assignment mechanism, the
per-site domains and prefixes, the home router HA pair, and the overlays/tunnels that tie the
sites together. Switch-level home topology (jim/dave/brian, the ONT path) lives in
[sites/home/switches.md](sites/home/switches.md).

## Assignments

Every box declares `nixos.systems.<name>.assignments`, an attrset of *assignments* (one per
network the box is attached to). The option shape (`assignmentOpts` in
[`nixos/default.nix`](../nixos/default.nix)):

- `name` (defaults to the attribute name) and `altNames` — DNS names for the assignment.
- `visible` (default `true`) — whether DNS helpers include it.
- `domain` — DNS suffix for this assignment.
- `mtu` — interface MTU (applied via the network's `linkConfig.MTUBytes`).
- `ipv4.address` / `ipv4.mask` (default 24) / `ipv4.gateway` (defaults to host 1 of the
  prefix; set explicitly to `null` when there is no gateway) / `ipv4.genPTR`.
- `ipv6.address` (nullable — an assignment can be v4-only) / `ipv6.mask` (default 64) /
  `ipv6.iid` (SLAAC static token instead of a full address) / `ipv6.gateway` / `ipv6.genPTR`.

`extraAssignments` is a second, nested level for addresses that belong *to* a network but not
to any single box — the home routers use it for their floating VIP entries (`router-hi`,
`router-lo`, `router-ut`).

All assignments are aggregated into `nixos.allAssignments` — every system's `assignments`
merged with every system's `extraAssignments` — and passed to every module as the
`allAssignments` argument, so any box can route to any other box's addresses without
hardcoding. A flake-wide assertion fails evaluation if any IPv4 or IPv6 address appears in
more than one assignment. Each box also receives its own assignments as the `assignments`
module argument.

Two pieces of machinery consume assignments:

- `lib.my.networkdAssignment` ([`lib/default.nix`](../lib/default.nix)) renders an assignment
  as a `systemd.network` network: static `address`/`gateway`, MTU, LLDP, and IPv6 RA handling
  (`IPv6AcceptRA` when there's no static gateway or a static `iid` is set, with
  `Token = static:<iid>`).
- `mkSystem` defaults `networking.hostName` to `assignments.internal.name` (falling back to
  the system name) and `networking.domain` to `assignments.internal.domain`. The shared
  `network` module sets a fallback domain of `int.nul.ie` for boxes without one.

## Domains

The public domain is `nul.ie` (`lib.my.c.pubDomain`). Each site has its own internal domain
(constants in [`lib/constants.nix`](../lib/constants.nix)):

| Site | Domain |
|---|---|
| colony | `ams1.int.nul.ie` |
| home | `h.nul.ie` |
| britway | `lon1.int.nul.ie` |
| britnet | `bhx1.int.nul.ie` |
| kelder | `hentai.engineer` |

## colony

The colony box is a hosted server in Amsterdam (`ams1`); its public edge is the `estuary` VM
(`94.142.240.44`, `2a02:898:0:20::329:1`), which NATs and filters for everything behind it.
The internal prefixes (`lib.my.c.colony.prefixes`) are carved from `10.100.0.0/16` and
`2a0e:97c0:4d2:10::/60`:

| Network | IPv4 | IPv6 | Purpose |
|---|---|---|---|
| `base` | `10.100.0.0/24` | `2a0e:97c0:4d2:10::/64` | Base/management LAN (bridge on the host; estuary is `.1`) |
| `vms` | `10.100.1.0/24` | `2a0e:97c0:4d2:11::/64` | VM network (host is `.1`, hands out RAs) |
| `ctrs` | `10.100.2.0/24` | `2a0e:97c0:4d2:12::/64` | `systemd-nspawn` containers on the `shill` VM |
| `oci` | `10.100.3.0/24` | `2a0e:97c0:4d2:13::/64` | Podman/OCI workloads on the `whale2` VM |
| `qclk` | `10.100.4.0/24` | — | WireGuard endpoint instances in the `qclk` container |

On top of that: `p2pTunnels` (`10.100.5.0/24`) holds point-to-point tunnel /30s (see
[WireGuard tunnels](#wireguard-point-to-point-tunnels)); the `as211024` mesh gets
`10.100.50.0/24` + `2a0e:97c0:4df::/64` (see [the L2 mesh](#the-as211024-l2-mesh)); and the
`cust` block (`10.100.100.0/24`, `2a0e:97c0:4d2:2000::/56`) plus the `vip1`/`vip2`/`vip3`
public blocks and the per-customer `mail` / `darts` / `jam` prefixes carry customer-facing
services with their own public addresses (announced by BGP, routed via the host).

## home

The home site prefixes (`lib.my.c.home.prefixes`) come from `192.168.64.0/18` and
`2a0e:97c0:4d0::/60`, with VLAN IDs from `lib.my.c.home.vlans`:

| Network | VLAN | IPv4 | IPv6 | MTU | Purpose |
|---|---|---|---|---|---|
| `core` | — (macvlan) | `192.168.64.0/24` | — | 1500 | Router-to-router/core link |
| `hi` | 100 | `192.168.68.0/22` | `2a0e:97c0:4d0:1::/64` | 9000 | High-speed LAN (jumbo frames) |
| `lo` | 110 | `192.168.72.0/21` | `2a0e:97c0:4d0:2::/64` | 1500 | General LAN |
| `untrusted` | 120 | `192.168.80.0/24` | `2a0e:97c0:4d0:3::/64` | 1500 | Untrusted / IoT |
| `modem` | 130 (`wan`) | `192.168.0.0/24` | — | — | Virgin Media modem management (stream) |
| `ont` | 140 (`wan-pon-ont`) | `192.168.100.0/24` | — | — | Digiweb ONT management (river) |

Two more WAN-side VLANs exist: `pon-isp` (10), the ISP VLAN Digiweb delivers at the ONT and
which is trunked untranslated to river, and `wan-pon-isp` (141), reserved for a future
multi-ONT translation scheme — see
[sites/home/switches.md](sites/home/switches.md) for the fabric side.

The routers themselves (`river` = host 1, `stream` = host 2 in each prefix) are built from one
definition, [`nixos/boxes/home/routing-common`](../nixos/boxes/home/routing-common/default.nix),
parameterised by an index (`0` = river, `1` = stream) that derives per-box addresses, DHCP
pool splits, VRRP state/priority and DNS `ns` numbering.

### Router VIPs

Clients never use a router's real address: each client VLAN has a floating VIP
(`lib.my.c.home.vips`) that follows the VRRP master. The VIPs are also declared as
`extraAssignments` (`router-hi`/`router-lo`/`router-ut`) so they appear in `allAssignments`
and DNS:

| Assignment | IPv4 | IPv6 |
|---|---|---|
| `router-hi` | `192.168.71.254/22` | `2a0e:97c0:4d0:1::ffff/64` |
| `router-lo` | `192.168.79.254/21` | `2a0e:97c0:4d0:2::ffff/64` |
| `router-ut` | `192.168.80.254/24` | `2a0e:97c0:4d0:3::ffff/64` |

There is also a mesh-side VIP (`as211024`): `10.100.50.4` and `2a0e:97c0:4df:0:1::ffff`,
which the other sites use as their next-hop into the home prefixes.

### Router HA

- **VRRP via `keepalived`** ([`routing-common/keepalived.nix`](../nixos/boxes/home/routing-common/keepalived.nix)):
  separate v4/v6 instances (router IDs 51/52) on the `lan-core` link; index 0 (river) starts
  as `MASTER`, priorities are `255 - index`. Track scripts ping public v4/v6 anycast targets
  and demote a router whose WAN is down. All VIPs of a family move together.
- **Clients get the VIP as gateway *and* DNS.** `kea` hands out `vips.<vlan>.v4` as both
  `routers` and `domain-name-servers`, with the two routers serving disjoint pool halves;
  `radvd` advertises the v6 VIP as RDNSS (the `untrusted` VLAN gets Cloudflare instead) and
  is started/stopped by keepalived's `notify_master`/`notify_backup` hooks so only the master
  sends RAs.
- **`pdns-recursor` binds the VIPs directly** ([`routing-common/dns.nix`](../nixos/boxes/home/routing-common/dns.nix)),
  with `net.ipv4.ip_nonlocal_bind` / `net.ipv6.ip_nonlocal_bind` so the backup can listen on
  addresses it doesn't currently hold — failover doesn't depend on client resolver timeouts.
  The recursor forwards the site's zones to the local authoritative PowerDNS on `127.0.0.1:5353`.
- **`wan-online.target`** is a shared, initially-inert systemd target meaning "the public
  IPv4 WAN route is up". `routing-common` only declares it; each box wires how it's reached —
  stream gates it on a oneshot that waits for the DHCP default route on `wan`, river's `pppd`
  `ip-up`/`ip-down` hooks start/stop it. Consumers (e.g. `ipsec`, the RA-default-route
  cleanup) attach **to** it with `wantedBy` + `partOf` + `after`, never `requires`/`wants`,
  so the target is never pulled in early and services re-load on WAN flap.

### WAN paths (summary)

- **river** (a VM on `palace`): PPPoE to Digiweb via `services.pppd`, running directly on the
  ISP's VLAN 10 (`wan-pon-isp`, trunked untranslated through the switches; baby-jumbo MTU 1508
  so the PPP session is a clean 1500). The static IP is requested in IPCP; the pppd hooks own
  `wan-online.target`. The ONT's management subnet (`192.168.100.0/24`) is reached on
  `wan-pon-ont` (VLAN 140, PVID'd at the brian switch), where river takes `.100`.
- **stream** (bare metal): DHCP on the Virgin Media cable modem (VLAN 130) on `wan`, with a
  static modem-management address (`192.168.0.100/24`) alongside the public lease, and CAKE
  egress/ingress shaping via `wan-ifb`.

The full fabric story — which switch port carries what, why VLAN 10 is trunked untranslated,
and the multi-ONT plan — is in [sites/home/switches.md](sites/home/switches.md); the
`my.homeRouter.*` options (`dns.wanSkipBroadcasts`, `firewall.untrustedRejectV4`) let each box
tell `routing-common` about subnets sharing its WAN interface.

## The AS211024 L2 mesh

The edge routers are joined by a layer-2 mesh, defined once as `nixos.vpns.l2.as211024` in
[`nixos/boxes/colony/vms/estuary/default.nix`](../nixos/boxes/colony/vms/estuary/default.nix)
and realised on each member by the [`l2mesh` module](../nixos/modules/l2mesh.nix):

- **Members**: `estuary`, `river`, `stream`, `britway`, peering on their public addresses.
- **Transport**: VXLAN (VNI 211024, UDP port 4789) with static per-peer FDB entries and
  UDP-encapsulated IPsec in transport mode via Libreswan (authentication-only by default;
  `security.encrypt` would switch ESP from `null-sha256` to AES-GCM). The PSK is the shared
  `l2mesh/as211024.key` secret, expanded into `/run/l2mesh.secrets` at `ipsec` start.
- **Overlay addressing**: `10.100.50.0/24` / `2a0e:97c0:4df::/64`; the interface MTU is
  computed from the physical MTU minus VXLAN/UDP/IPsec overhead. Each router holds
  `10.100.50.<n>` (estuary `.1`, river `.2`, stream `.3`, britway `.5`).
- **Routing over it**: the home routers route the colony prefixes via estuary and the
  Tailscale prefixes via britway; estuary and britway route the home prefixes via the
  `10.100.50.4` VIP. The home IPv6 **default** route also runs over the mesh, via britway
  (hence the recursor's IPv4-only upstream pinning noted in
  [`routing-common/dns.nix`](../nixos/boxes/home/routing-common/dns.nix)). The `nftTrust`
  snippet in `lib.my.c.as211024` lets trusted inter-site traffic (colony, home, mesh,
  Tailscale prefixes) through the edge firewalls.

## BGP

Both edge routers run `bird2` as AS211024:

- **estuary** ([`bgp.nix`](../nixos/boxes/colony/vms/estuary/bgp.nix)): full table from
  ColoClue (AS8283) over two sessions per family, plus IPv6 transit from iFog and Hurricane
  Electric; peering at the Frys-IX, NL-ix and FogIXP route servers and with various networks
  (Meta, Cloudflare, Apple, LUJE.net, …); a `bgp.tools` monitoring session. Static routes pull
  the customer VIP blocks out of the `base` network and the internal/home IPv6 prefixes out of
  the mesh.
- **britway** ([`bgp.nix`](../nixos/boxes/britway/bgp.nix)): Vultr transit (AS64515,
  MD5-passworded from a secret) and a `bgp.tools` session, originating the internal, colony
  and home IPv6 prefixes.

## WireGuard point-to-point tunnels

Separate from the mesh, estuary terminates several networkd-managed WireGuard tunnels (private
keys in per-box secrets):

| Tunnel | Port | Remote / prefix | Notes |
|---|---|---|---|
| estuary ↔ kelder | 51820 | kelder holds `94.142.242.254/32` | kelder's public presence is a colony /32 routed over the tunnel |
| estuary ↔ hillcrest | 51822 | `10.100.5.0/30` | point-to-point /30 out of `p2pTunnels` |
| estuary ↔ john-valorant | 51823 | `10.100.5.4/30` | point-to-point /30 out of `p2pTunnels` |

Additionally, the `qclk` container on `shill` runs its own WireGuard instances on port 51821
out of `10.100.4.0/24`, and `britnet` hosts a road-warrior style WireGuard VPN on port 51820
serving `10.200.0.0/24` / `fdfb:5ebf:6e84::/64`.

## Tailscale / headscale

Tailscale runs against a self-hosted **headscale** control plane on britway
([`tailscale.nix`](../nixos/boxes/britway/tailscale.nix)) at `https://hs.nul.ie`: Google OIDC
login, SQLite state, MagicDNS under `ts.nul.ie`, and split DNS that resolves the colony and
home internal domains through their site resolvers. The tailnet prefixes are
`100.64.0.0/10` / `fd7a:115c:a1e0::/48`.

Notable nodes:

- **waffletail** (container on `shill`) — the colony subnet router: advertises the colony
  prefixes, acts as an exit node, and SNATs tailnet traffic into the colony networks.
- **britway** — advertises the home prefixes (routed via the mesh) and is also an exit node.
- Other boxes join with the shared `tailscale-auth.key` auth-key secret.
