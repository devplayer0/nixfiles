# Networking

This page describes how addressing works across the boxes: the assignment mechanism, the
per-site domains and prefixes, the home router HA pair, and the overlays/tunnels that tie the
sites together. Switch-level home topology (jim/dave/brian, the ONT path) lives in
[sites/home/switches.md](sites/home/switches.md).

## Assignments

Every box declares `nixos.systems.<name>.assignments`, an attrset of *assignments* (one per
network the box is attached to). The option definition (`assignmentOpts` in
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

## Box assignments

Every box's `assignments` (plus the routers' floating VIP `extraAssignments`), grouped first by site
and then by assignment key. Generated from `nixos.allAssignments` by
`nix run .#update-docs-assignments`; CI keeps it current. Only the **Notes** column is hand-written —
edit prose there, never the other generated cells.

### colony

<!-- assignments: colony -->
<!-- assignments-start -->
<!-- assignments-end -->

### home

<!-- assignments: home -->
<!-- assignments-start -->
<!-- assignments-end -->

### remote

<!-- assignments: remote -->
<!-- assignments-start -->
<!-- assignments-end -->

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

#### VRRP

[`routing-common/keepalived.nix`](../nixos/boxes/home/routing-common/keepalived.nix) defines separate
v4/v6 instances (router IDs 51/52) on `lan-core`. Index 0 (`river`) starts as `MASTER`, priorities
are `255 - index`, and track scripts demote a router whose WAN checks fail. All VIPs of an address
family move together.

#### Client gateway and DNS

`kea` hands out `vips.<vlan>.v4` as both `routers` and `domain-name-servers`, with the two routers
serving disjoint pool halves. `radvd` advertises the v6 VIP as RDNSS (`untrusted` gets Cloudflare)
and keepalived's `notify_master`/`notify_backup` hooks ensure that only the master sends RAs.

#### DNS binding

`pdns-recursor` binds the VIPs directly; see
[`routing-common/dns.nix`](../nixos/boxes/home/routing-common/dns.nix). The
`net.ipv4.ip_nonlocal_bind` / `net.ipv6.ip_nonlocal_bind` settings let the backup listen before it
owns the addresses, so failover does not depend on client resolver timeouts. The recursor forwards
the site's zones to authoritative PowerDNS on `127.0.0.1:5353`.

#### `wan-online.target`

This shared, initially inert systemd target means "the public IPv4 WAN route is up".
`routing-common` only declares it: `stream` gates it on a oneshot that waits for the DHCP default
route on `wan`, while `river`'s `pppd` hooks start and stop it. Consumers such as `ipsec` attach with
`wantedBy` + `partOf` + `after`, never `requires`/`wants`, so they cannot pull the target in early
and they reload on WAN flap.

### WAN paths (summary)

#### `river`

The VM on `palace` runs Digiweb PPPoE directly on VLAN 10 (`vlans.pon-isp`), trunked untranslated
through the switches. The carrying interface is named `wan-pon-isp`; VLAN ID 141 with that name is
reserved for a future translation scheme. MTU 1508 preserves a 1500-byte PPP session, IPCP requests
the static address, and the `pppd` hooks own `wan-online.target`. `wan-pon-ont` (VLAN 140) reaches
the ONT management subnet at `192.168.100.0/24`, where `river` takes `.100`.

#### `stream`

The bare-metal backup uses DHCP from the Virgin Media modem on `wan` (VLAN 130), keeps a static
`192.168.0.100/24` management address beside the public lease, and applies CAKE shaping through
`wan-ifb`.

The full fabric story — which switch port carries what, why VLAN 10 is trunked untranslated,
and the multi-ONT plan — is in [sites/home/switches.md](sites/home/switches.md); the
`my.homeRouter.*` options (`dns.wanSkipBroadcasts`, `firewall.untrustedRejectV4`) let each box
tell `routing-common` about subnets sharing its WAN interface.

## The AS211024 L2 mesh

The edge routers are joined by a layer-2 mesh, defined once as `nixos.vpns.l2.as211024` in
[`nixos/boxes/colony/vms/estuary/default.nix`](../nixos/boxes/colony/vms/estuary/default.nix)
and realised on each member by the [`l2mesh` module](../nixos/modules/l2mesh.nix):

### Members

`estuary`, `river`, `stream` and `britway` peer on their public addresses.

### Transport

VXLAN (VNI 211024, UDP port 4789) uses static per-peer FDB entries and UDP-encapsulated IPsec in
Libreswan transport mode. It authenticates without encryption by default; `security.encrypt`
switches ESP from `null-sha256` to AES-GCM. The shared `l2mesh/as211024.key` PSK is expanded into
`/run/l2mesh.secrets` when `ipsec` starts.

### Overlay addressing

The overlay uses `10.100.50.0/24` / `2a0e:97c0:4df::/64`. Each router holds `10.100.50.<n>`:
`estuary` `.1`, `river` `.2`, `stream` `.3`, and `britway` `.5`. Interface MTU is calculated from
the physical MTU minus VXLAN/UDP/IPsec overhead.

### Routing

The home routers route colony prefixes via `estuary` and Tailscale prefixes via `britway`;
`estuary` and `britway` route home prefixes through the `10.100.50.4` VIP. The home IPv6 default
route also crosses the mesh through `britway`, which is why the recursor pins its upstreams to IPv4
as noted in [`routing-common/dns.nix`](../nixos/boxes/home/routing-common/dns.nix). The `nftTrust`
snippet in `lib.my.c.as211024` admits trusted colony, home, mesh and Tailscale prefixes at the edge
firewalls.

## BGP

Both edge routers run `bird2` as AS211024.

### `estuary`

The colony edge takes a full table from ColoClue, IPv6 transit from iFog and Hurricane Electric,
and peers through the Frys-IX, NL-ix and FogIXP route servers. It also has direct and monitoring
sessions; the complete peer table and originated routes live in [estuary.md](sites/colony/estuary.md#bgp).

### `britway`

The London edge uses secret-backed MD5 authentication for Vultr transit (AS64515), connects to
`bgp.tools`, and originates the internal, colony and home IPv6 prefixes. See
[britway.md](remote/britway.md) for its box-specific routing detail.

## WireGuard point-to-point tunnels

Separate from the mesh, a few boxes run their own WireGuard (private keys in per-box secrets):

- **estuary** terminates point-to-point tunnels to `kelder`, `hillcrest` and `john-valorant`,
  addressed out of `p2pTunnels` — see
  [estuary.md](sites/colony/estuary.md#wireguard-tunnels) for the per-tunnel ports and prefixes.
- **`qclk`** (container on `shill`) runs its own WireGuard on port 51821 out of `10.100.4.0/24`
  — see [qclk.md](sites/colony/shill/containers/qclk.md).
- **`britnet`** hosts a road-warrior WireGuard VPN on port 51820 serving `10.200.0.0/24` /
  `fdfb:5ebf:6e84::/64` — see [britnet.md](remote/britnet.md).

## Tailscale / headscale

Tailscale runs against a self-hosted **headscale** control plane on britway at `https://hs.nul.ie`
(OIDC, MagicDNS, split DNS — see [britway.md](remote/britway.md)). The tailnet prefixes are
`100.64.0.0/10` / `fd7a:115c:a1e0::/48`.

Notable nodes:

- **waffletail** (container on `shill`) — the colony subnet router: advertises the colony
  prefixes, acts as an exit node, and SNATs tailnet traffic into the colony networks.
- **britway** — advertises the home prefixes (routed via the mesh) and is also an exit node.
- Other boxes join with the shared `tailscale-auth.key` auth-key secret.
