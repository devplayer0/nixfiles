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
#### `internal`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`chatterbox`](sites/colony/shill/containers/chatterbox.md) | `10.100.2.5/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::5/64` | ams1.int.nul.ie |  |
| [`colony`](sites/colony/colony.md) | `94.142.241.224/32` | `2a0e:97c0:4d2:10::2/64` | ams1.int.nul.ie |  |
| [`colony-psql`](sites/colony/shill/containers/colony-psql.md) | `10.100.2.4/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::4/64` | ams1.int.nul.ie |  |
| `enshrouded-oci` | `10.100.3.5/24 gw 10.100.3.1` | `2a0e:97c0:4d2:13::5/64` | ams1.int.nul.ie | Enshrouded OCI container on [`whale2`](sites/colony/whale2.md#game-servers); disabled |
| [`estuary`](sites/colony/estuary.md) | `94.142.240.44/24 gw 94.142.240.254` | `2a02:898:0:20::329:1/64 gw 2a02:898:0:20::1` | ams1.int.nul.ie |  |
| [`gam`](sites/colony/shill/containers/gam.md) | `10.100.2.11/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::b/64` | ams1.int.nul.ie |  |
| [`git`](sites/colony/git.md) | `94.142.241.117/32` | `2a0e:97c0:4d2:11::4/64` | ams1.int.nul.ie |  |
| `graeme-oci` | `10.100.3.8/24 gw 10.100.3.1` | `2a0e:97c0:4d2:13::8/64` | ams1.int.nul.ie | Minecraft OCI container on [`whale2`](sites/colony/whale2.md#game-servers) |
| [`jackflix`](sites/colony/shill/containers/jackflix.md) | `10.100.2.6/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::6/64` | ams1.int.nul.ie |  |
| `kevcraft-oci` | `10.100.3.6/24 gw 10.100.3.1` | `2a0e:97c0:4d2:13::6/64` | ams1.int.nul.ie | Minecraft OCI container on [`whale2`](sites/colony/whale2.md#game-servers) |
| `kinkcraft-oci` | `10.100.3.7/24 gw 10.100.3.1` | `2a0e:97c0:4d2:13::7/64` | ams1.int.nul.ie | Minecraft OCI container on [`whale2`](sites/colony/whale2.md#game-servers) |
| [`middleman`](sites/colony/shill/containers/middleman.md) | `10.100.2.2/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::2/64` | ams1.int.nul.ie |  |
| [`object`](sites/colony/shill/containers/object.md) | `10.100.2.7/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::7/64` | ams1.int.nul.ie |  |
| [`qclk`](sites/colony/shill/containers/qclk.md) | `10.100.2.10/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::a/64` | ams1.int.nul.ie |  |
| [`shill`](sites/colony/shill/README.md) | `94.142.241.225/32` | `2a0e:97c0:4d2:11::2/64` | ams1.int.nul.ie |  |
| `simpcraft-oci` | `10.100.3.3/24 gw 10.100.3.1` | `2a0e:97c0:4d2:13::3/64` | ams1.int.nul.ie | Minecraft OCI container on [`whale2`](sites/colony/whale2.md#game-servers) |
| `simpcraft-staging-oci` | `10.100.3.4/24 gw 10.100.3.1` | `2a0e:97c0:4d2:13::4/64` | ams1.int.nul.ie | Minecraft staging OCI container on [`whale2`](sites/colony/whale2.md#game-servers); disabled |
| [`toot`](sites/colony/shill/containers/toot.md) | `10.100.2.8/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::8/64` | ams1.int.nul.ie |  |
| `valheim-oci` | `10.100.3.2/24 gw 10.100.3.1` | `2a0e:97c0:4d2:13::2/64` | ams1.int.nul.ie | Valheim OCI container on [`whale2`](sites/colony/whale2.md#game-servers) |
| [`vaultwarden`](sites/colony/shill/containers/vaultwarden.md) | `10.100.2.3/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::3/64` | ams1.int.nul.ie |  |
| [`waffletail`](sites/colony/shill/containers/waffletail.md) | `10.100.2.9/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::9/64` | ams1.int.nul.ie |  |
| [`whale2`](sites/colony/whale2.md) | `94.142.241.226/32` | `2a0e:97c0:4d2:11::3/64` | ams1.int.nul.ie |  |

#### `as211024`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`estuary`](sites/colony/estuary.md) | `10.100.50.1/24` | `2a0e:97c0:4df::1/64` | — |  |

#### `base`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`estuary`](sites/colony/estuary.md) | `10.100.0.1/24` | `2a0e:97c0:4d2:10::1/64` | ams1.int.nul.ie |  |

#### `ctrs`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`shill`](sites/colony/shill/README.md) | `10.100.2.1/24` | `2a0e:97c0:4d2:12::1/64` | ams1.int.nul.ie |  |

#### `oci`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`whale2`](sites/colony/whale2.md) | `10.100.3.1/24` | `2a0e:97c0:4d2:13::1/64` | ams1.int.nul.ie |  |

#### `qclk`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`qclk`](sites/colony/shill/containers/qclk.md) | `10.100.4.1/24` | — | — |  |

#### `routing`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`colony`](sites/colony/colony.md) | `10.100.0.2/24 gw 10.100.0.1` | — | ams1.int.nul.ie |  |
| [`git`](sites/colony/git.md) | `10.100.1.4/24 gw 10.100.1.1` | — | ams1.int.nul.ie |  |
| [`shill`](sites/colony/shill/README.md) | `10.100.1.2/24 gw 10.100.1.1` | — | ams1.int.nul.ie |  |
| [`whale2`](sites/colony/whale2.md) | `10.100.1.3/24 gw 10.100.1.1` | — | ams1.int.nul.ie |  |

#### `tailscale`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`waffletail`](sites/colony/shill/containers/waffletail.md) | `100.64.0.5/32` | `fd7a:115c:a1e0::5/128` | — |  |

#### `vms`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`colony`](sites/colony/colony.md) | `10.100.1.1/24` | `2a0e:97c0:4d2:11::1/64` | ams1.int.nul.ie |  |
<!-- assignments-end -->

### home

<!-- assignments: home -->
<!-- assignments-start -->
#### `as211024`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`river`](sites/home/river.md) | `10.100.50.2/24` | `2a0e:97c0:4df:0:1::1/64 gw 2a0e:97c0:4df:0:2::1` | — |  |
| [`stream`](sites/home/stream.md) | `10.100.50.3/24` | `2a0e:97c0:4df:0:1::2/64 gw 2a0e:97c0:4df:0:2::1` | — |  |

#### `core`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`palace`](sites/home/palace.md) | `192.168.64.20/24` | — | h.nul.ie |  |
| [`river`](sites/home/river.md) | `192.168.64.1/24` | — | h.nul.ie |  |
| [`stream`](sites/home/stream.md) | `192.168.64.2/24` | — | h.nul.ie |  |
| [`unifi`](sites/home/sfh/containers/unifi.md) | `192.168.64.21/24` | — | h.nul.ie |  |

#### `hi`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`castle`](sites/home/castle.md) | `192.168.68.40/22 gw 192.168.71.254` | `2a0e:97c0:4d0:1::3:1/64` | h.nul.ie |  |
| [`cellar`](sites/home/cellar.md) | `192.168.68.80/22 gw 192.168.71.254` | `2a0e:97c0:4d0:1::4:1/64` | h.nul.ie |  |
| [`hass`](sites/home/sfh/containers/hass.md) | `192.168.68.103/22 gw 192.168.71.254` | `2a0e:97c0:4d0:1::5:3/64` | h.nul.ie |  |
| [`palace`](sites/home/palace.md) | `192.168.68.22/22 gw 192.168.71.254` | `2a0e:97c0:4d0:1::2:1/64` | h.nul.ie |  |
| [`river`](sites/home/river.md) | `192.168.68.1/22` | `2a0e:97c0:4d0:1::1/64` | h.nul.ie |  |
| `router-hi` | `192.168.71.254/22 gw 192.168.68.1` | `2a0e:97c0:4d0:1::ffff/64` | h.nul.ie | Floating VIP shared by [`river`](sites/home/river.md) and [`stream`](sites/home/stream.md) |
| [`sfh`](sites/home/sfh/README.md) | `192.168.68.81/22 gw 192.168.71.254` | `2a0e:97c0:4d0:1::4:2/64` | h.nul.ie |  |
| [`stream`](sites/home/stream.md) | `192.168.68.2/22` | `2a0e:97c0:4d0:1::2/64` | h.nul.ie |  |
| [`unifi`](sites/home/sfh/containers/unifi.md) | `192.168.68.100/22 gw 192.168.71.254` | `2a0e:97c0:4d0:1::5:1/64` | h.nul.ie |  |

#### `lo`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`hass`](sites/home/sfh/containers/hass.md) | `192.168.72.103/21` | `2a0e:97c0:4d0:2::5:3/64` | h.nul.ie |  |
| [`river`](sites/home/river.md) | `192.168.72.1/21` | `2a0e:97c0:4d0:2::1/64` | h.nul.ie |  |
| `router-lo` | `192.168.79.254/21 gw 192.168.72.1` | `2a0e:97c0:4d0:2::ffff/64` | h.nul.ie | Floating VIP shared by [`river`](sites/home/river.md) and [`stream`](sites/home/stream.md) |
| [`stream`](sites/home/stream.md) | `192.168.72.2/21` | `2a0e:97c0:4d0:2::2/64` | h.nul.ie |  |

#### `untrusted`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`river`](sites/home/river.md) | `192.168.80.1/24` | `2a0e:97c0:4d0:3::1/64` | h.nul.ie |  |
| `router-ut` | `192.168.80.254/24 gw 192.168.80.1` | `2a0e:97c0:4d0:3::ffff/64` | h.nul.ie | Floating VIP shared by [`river`](sites/home/river.md) and [`stream`](sites/home/stream.md) |
| [`stream`](sites/home/stream.md) | `192.168.80.2/24` | `2a0e:97c0:4d0:3::2/64` | h.nul.ie |  |
<!-- assignments-end -->

### remote

<!-- assignments: remote -->
<!-- assignments-start -->
#### `internal`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`kelder-acquisition`](remote/kelder/containers/kelder-acquisition.md) | `172.16.64.2/24 gw 172.16.64.1` | — | hentai.engineer |  |
| [`kelder-spoder`](remote/kelder/containers/kelder-spoder.md) | `172.16.64.3/24 gw 172.16.64.1` | — | hentai.engineer |  |

#### `allhost`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`britnet`](remote/britnet.md) | `77.74.199.67/24 gw 77.74.199.1` | `2a12:ab46:5344:99::a/64 gw 2a12:ab46:5344::1` | bhx1.int.nul.ie |  |

#### `as211024`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`britway`](remote/britway.md) | `10.100.50.5/24` | `2a0e:97c0:4df:0:2::1/64` | — |  |

#### `ctrs`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`kelder`](remote/kelder/README.md) | `172.16.64.1/24` | — | hentai.engineer |  |

#### `estuary`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`kelder`](remote/kelder/README.md) | `94.142.242.254/32` | — | — |  |

#### `vpn`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`britnet`](remote/britnet.md) | `10.200.0.1/24` | `fdfb:5ebf:6e84::1/64` | — |  |

#### `vultr`

| Box | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|
| [`britway`](remote/britway.md) | `45.76.141.188/23 gw 45.76.140.1` | `2001:19f0:7402:128b::1/64` | lon1.int.nul.ie |  |
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

This layout is expected to change: [`portcullis`](sites/colony/portcullis.md) is bare-metal edge
hardware headed for Nikhef that will take over most of `estuary`'s routing. It has no colony
assignments yet (only a home `hi` one, from being staged at home) and the replacement topology is
still being designed.

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

Statically-addressed boxes (the servers on `hi`) don't run DHCP, so they'd otherwise learn a
resolver only from the v6 RA RDNSS — which vanishes when v6 is disabled, taking DNS with it. They
instead anchor DNS on the VIPs via the shared `lib.my.c.home.vlanDns "<vlan>"` fragment, which sets
`DNS` to `vips.<vlan>.{v4,v6}` and `Domains` to the advertised search list; the always-present
static v4 VIP keeps resolution working even with v6 down.

#### DNS binding

`pdns-recursor` binds the VIPs directly; see
[`routing-common/dns.nix`](../nixos/boxes/home/routing-common/dns.nix). The
`net.ipv4.ip_nonlocal_bind` / `net.ipv6.ip_nonlocal_bind` settings let the backup listen before it
owns the addresses, so failover does not depend on client resolver timeouts. The recursor forwards
the site's zones to authoritative PowerDNS on `127.0.0.1:5353`. The generated
[DNS reference](reference/dns.md) lists the live forward and reverse records; the authoritative
servers allow its AXFRs from the shared internal prefixes and the colony site's egress address.

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

### ESP throughput

ESP is the mesh's throughput limit rather than VXLAN — encapsulation is close to free, and on a
small box the crypto is what costs. The kernel processes a single SA on a single core, so per-peer
throughput is capped by one core however many the box has. That limit binds per peer rather than
per box, so a router spreads naturally across its peers.

Two things follow for configuration:

- The `esp4_offload` / `esp6_offload` modules provide GSO/GRO batching for ESP and are **not**
  autoloaded when an SA is created. The [`l2mesh` module](../nixos/modules/l2mesh.nix) loads the
  one matching each secured mesh's underlay family; without them throughput is around a third
  lower, for more CPU.
- `security.encrypt = false` does not save CPU on hardware with AES-NI — it measured slower than
  AES-GCM. GCM resolves to a single fused accelerated implementation, while the authenticate-only
  path falls back to a generic `authenc(hmac(sha256),ecb(cipher_null))` composition.

#### NIC crypto offload

No mesh uses it, and the `esp4_offload` / `esp6_offload` modules above are unrelated to it — those
are software GSO/GRO batching. Hardware ESP offload is a separate XFRM feature that Libreswan only
requests for connections setting `nic-offload=yes`, which the
[`l2mesh` module](../nixos/modules/l2mesh.nix) does not.

[`portcullis`](sites/colony/portcullis.md)'s 82599ES ports advertise `esp-hw-offload` and the
offload does work, but not for anything the meshes could use. Measured on the box by installing
SAs directly with `ip xfrm` and watching `ixgbe`'s `tx_ipsec` counter:

| SA | Result |
|---|---|
| `et10g-0`, transport, AES-GCM-128 | offload active — `mode crypto` against the physical port |
| `et10g-0`, transport, AES-GCM-256 | rejected: *"IPsec hw offload only supports keys up to 128 bits with a 32 bit salt"* |
| `et10g-0`, **tunnel** mode | rejected: *"Unsupported mode for ipsec offload"* |
| `lan-hi` (a VLAN on `et10g-0`) | **accepted with the offload silently dropped** — software crypto |
| `et2g5-0` (I226-V) | accepted, offload silently dropped — `igc` has none |

Two traps are worth knowing. Binding an SA to a device that cannot offload is **not** an error:
`xfrm_dev_state_add` returns success having cleared the device, so the SA looks fine and quietly
runs in software. And a VLAN interface never offloads — it carries no `xfrmdev_ops`, and
`esp-hw-offload` reads `off [fixed]` on it even when its parent supports the feature.

The second trap is the decisive one here. Even with the offload genuinely active against
`et10g-0`, driving traffic through the SA left `tx_ipsec` at zero, because the packets egress
`lan-hi` and the kernel only offloads when the SA's device matches the egress device. Every address
`portcullis` holds is on a VLAN, so an SA would have to be bound to an untagged physical port to
see the hardware at all.

So adopting it would mean dropping to a 128-bit key to suit one NIC family, keeping the underlay
off VLANs, and forgoing `udpEncapsulation` — `xfrm_dev_offload_ok` refuses any SA carrying
`encap`. That is not a trade worth making for a mesh that has to run across boxes with no offload
at all.

#### pcrypt

`pcrypt` parallelises an SA's crypto across cores via padata and does lift the per-SA ceiling. It
is not enabled on any box here, and is recorded as an option rather than a recommendation:

- It cannot be named in the SA — `ip xfrm` and the kernel both validate AEAD names against a fixed
  list. It is engaged instead by registering a `pcrypt(...)`-wrapped instance under the standard
  algorithm name at a higher priority, over `NETLINK_CRYPTO` (`CONFIG_CRYPTO_USER`). `crconf` is
  the usual tool for that and is not packaged in nixpkgs.
- The registration is global: it redirects every user of that algorithm on the box, not just the
  mesh, and would have to run before `ipsec` starts.
- A single-threaded submit path remains, so it does not scale with core count, and it trades
  latency and packet ordering for throughput.

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
