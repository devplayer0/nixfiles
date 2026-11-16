# stream

A physical Intel home router with a DHCP WAN from the Virgin Media cable modem. It forms the
redundant router pair with [`river`](river.md) and is dual-homed to both switches.

- **Source:** [`nixos/boxes/home/stream.nix`](../../../nixos/boxes/home/stream.nix) (shared router
  config: [`routing-common`](../../../nixos/boxes/home/routing-common), index 1)
- **Host:** physical
- **nixpkgs:** `mine`

## Hardware

| Component | Inventory |
|---|---|
| Platform | BROUNION R86S |
| CPU | Intel Celeron N5105 (4 cores / 4 threads) |
| Memory | 16 GiB |
| Storage | 512 GB Samsung SSD 970 PRO NVMe containing `/boot`, `/nix` and `/persist`; integrated 128 GB eMMC is present but is not used by the declared filesystems |
| Network | Three Intel I225-V 2.5G interfaces (`igc`) and a dual-port Mellanox ConnectX-3 10G SFP+ adapter (`mlx4_en`); `wan`, `lan-jim` and `lan-dave` use three of these ports |

The platform configuration enables `kvm-intel`, `intel_iommu=on` and Intel microcode updates.

## Role

At `routing-common` index 1, `stream` normally holds the secondary position in the router pair.
Pair-wide addressing, VIP, DHCP/DNS and failover behavior is documented in the
[`home` networking overview](../../networking.md#home) and [Router HA](../../networking.md#router-ha).
This page covers `stream`'s Virgin Media WAN, physical platform and redundant switch attachment.

## Network assignments

See the consolidated [network assignments](../../networking.md#box-assignments) table (this box: `stream`).

## WAN (Virgin Media DHCP)

A Quectel RM500U-EA 5G modem is being evaluated as a replacement for this WAN; it is bench-tested
only and nothing here depends on it yet. Note that its SIM is CGNAT, so it cannot carry the public
lease this section assumes — see [wwan.md](wwan.md).

### Link and addressing

`wan` is a renamed igc NIC (`00:f0:cb:ee:ca:dd`) on a physically separate connection to `jim`'s
`stream-wan` port. The Virgin Media modem connects to `shytzel`, which trunks
VLAN 130 to `jim`; `stream-wan` delivers it untagged to the box. See
[switches.md](switches.md) for the fabric side.

`DHCP=ipv4` pulls the public lease. `dhcpV4Config.UseDNS=false` points resolution at the local
recursor, and `IPv6AcceptRA=false` because public IPv6 arrives over the tunnel rather than this WAN.

### Management subnet

The static `192.168.0.100/24` address (host `.100` of `prefixes.modem.v4`) sits on `wan` without a
gateway, keeping the modem UI reachable alongside the DHCP lease.

### WAN readiness

`wan-wait-online.service` polls until the DHCP default route exists, then satisfies
`wan-online.target`. The route is the gate because the permanent modem address would make
networkd's wait-online report success before the public lease arrives, allowing `ipsec` to start
without its public `left=` address.

### Traffic shaping

Egress is shaped at the `wan` root qdisc. A `routing-common` `networkd-dispatcher` rule redirects
ingress through `tc`/`mirred` into `wan-ifb`; each direction has its own configured bandwidth and
uses the DOCSIS overhead preset.

### Per-box `routing-common` options

The modem's management subnet shares the `wan` interface, which `routing-common` itself knows
nothing about. This box sets `my.homeRouter.dns.wanSkipBroadcasts`
([`routing-common/default.nix`](../../../nixos/boxes/home/routing-common/default.nix)) to skip the
modem subnet's broadcast address when auto-selecting the router's own `wan` A record for the zone's
LUA record. `untrusted` clients can't reach the modem subnet: it's private, so the
[`untrusted` filter](../../networking.md#untrusted-clients) rejects it.

## Switching (RSTP)

`stream` is dual-homed to both switches: `lan-dave` (mlx4_en) and `lan-jim` (igc), both MTU 9000,
are ports of the shared `lan` bridge. `routing-common` owns the bridge, its STP setting and the
explicit `dave`/`jim` costs of 10/100. [`routing-common/mstpd.nix`](../../../nixos/boxes/home/routing-common/mstpd.nix)
runs a patched `mstpd` and forces RSTP once `lan` is configured, so exactly one uplink carries
traffic at a time and `dave` is preferred. (The remaining NICs are renamed `et2`/`et5` and left
unconfigured.)

The separate `wan` connection to `jim` is not a bridge port. Retaining it provides an isolated
untagged DHCP handoff for Virgin Media and a simple path for a future replacement direct-IP WAN.

## Deployment

`my.deploy.node.hostname` is currently commented out.

## Disabled printer services

`octoprint` and `mjpg-streamer` are defined but disabled (`enable = false`).

## Notable config files

- [`nixos/boxes/home/stream.nix`](../../../nixos/boxes/home/stream.nix) — box config: DHCP WAN,
  modem management, CAKE, `wan-online.target` gate and hardware link matching.
- [`nixos/boxes/home/routing-common/default.nix`](../../../nixos/boxes/home/routing-common/default.nix) —
  shared router definition, including the `lan` bridge and port preferences (index 1).
- [`nixos/boxes/home/routing-common/mstpd.nix`](../../../nixos/boxes/home/routing-common/mstpd.nix) —
  RSTP on the `lan` bridge.
