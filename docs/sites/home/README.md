# Home site

The home network (domain `h.nul.ie`): a redundant pair of routers in front of a VM host, an
NVMe-oF storage target, an IoT container host, and a workstation. The two routers — `river` (a VM)
and `stream` (a physical box) — are built from one shared
[`routing-common`](../../../nixos/boxes/home/routing-common) definition as an active/backup VRRP
pair, and everything clients touch (gateway, DNS) is a floating VIP that follows the master.

- **Source:** [`nixos/boxes/home/`](../../../nixos/boxes/home)

## Boxes

| Box | Role | Host |
|---|---|---|
| [`palace`](palace.md) | VM host | physical |
| [`river`](river.md) | Primary router (VRRP pair with `stream`) | VM on `palace` |
| [`stream`](stream.md) | Secondary router (VRRP pair with `river`) | physical |
| [`cellar`](cellar.md) | NVMe-oF / SPDK storage target | VM on `palace` |
| [`sfh`](sfh/README.md) | NixOS container host (containers on its page) | VM on `palace` |
| [`castle`](castle.md) | Workstation / gaming desktop | physical |

## Router VIPs

Clients use per-VLAN floating VIPs as their gateway and DNS server; `keepalived` moves them between
`river` and `stream`. The addresses, DHCP/RA behavior and failover mechanics are documented once in
[Router VIPs](../../networking.md#router-vips) and [Router HA](../../networking.md#router-ha).

## Networks

The site separates core management, high-MTU trusted traffic, general trusted traffic, untrusted
clients and the two WAN paths. VLAN IDs, prefixes, MTUs and router addressing live in the canonical
[`home` section of networking.md](../../networking.md#home).

## Switch fabric

The boxes hang off three hand-configured switches — `jim` and `dave` (MikroTik, RouterOS) and
`brian` (Ubiquiti, UniFi) — which are **not** managed by this flake. The physical topology, VLAN
map, the Digiweb WAN path (trunked VLAN 10 + PVID 140 at the ONT edge), and the multi-ONT plan are
documented in [switches.md](switches.md).

## Wireless APs

The Wi-Fi APs — `vibe` (MikroTik cAP ax) and `wave` (Cudy AX3000 on OpenWrt) — are dumb APs, also
**not** managed by this flake. The shared VLAN-trunk design, SSIDs, per-AP management addressing,
and the OpenWrt flash/config for `wave` are in [aps.md](aps.md).

## 5G WWAN

A Quectel RM500U-EA USB modem with a GoMo SIM is being evaluated as a replacement for `stream`'s
Virgin Media WAN. It is bench-tested only and not yet referenced by the flake; the module settings
it needs, the APN gotcha and the CGNAT consequences are in [wwan.md](wwan.md).
