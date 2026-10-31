# river

A home router VM on `palace` with a Digiweb PPPoE WAN on the ISP's VLAN 10. It forms the redundant
router pair with [`stream`](stream.md).

- **Source:** [`nixos/boxes/home/palace/vms/river.nix`](../../../nixos/boxes/home/palace/vms/river.nix)
  (shared router config: [`routing-common`](../../../nixos/boxes/home/routing-common), index 0)
- **Host:** VM on `palace`
- **nixpkgs:** `mine`

## Role

At `routing-common` index 0, `river` normally holds the primary position in the router pair.
Pair-wide addressing, VIP, DHCP/DNS and failover behavior is documented in the
[`home` networking overview](../../networking.md#home) and [Router HA](../../networking.md#router-ha).
This page covers `river`'s Digiweb WAN, VM platform, storage and netboot duties.

## Network assignments

See the consolidated [network assignments](../../networking.md#box-assignments) table (this box: `river`).

## WAN (Digiweb PPPoE)

### Link and addressing

`services.pppd` peer `digiweb` attaches directly to `wan-pon-isp`, the raw ISP VLAN 10
(`vlans.pon-isp`) trunked untranslated from the ONT. It normally reaches `river` through `brian`
and `dave`; the configured RSTP path through `jim` is intended to provide redundancy after
successful deployment and validation. See [switches.md](switches.md). The netdev has no L3
configuration and uses `MTUBytes=1508`, leaving a clean `mtu`/`mru 1500` after PPPoE overhead.

The static `84.203.124.128` address is requested through IPCP. The provider-wide credentials are
deliberately not secret; the peer persists indefinitely with LCP echo monitoring and ignores
Digiweb DNS in favor of the local recursor.

### Management subnet

`wan-pon-ont` (VLAN 140, PVID'd at `brian`) holds `192.168.100.100/24`, reaching the ONT UI at
`192.168.100.1`. The `.100` address follows `stream`'s modem-management convention.

### WAN readiness

The `pppd` hooks drive this shared gate with `DefaultDependencies=false`: `ip-up` installs the
link-scoped default route and starts the target, while `ip-down` stops it and removes the route.
`ipsec` and `ipv6-clear-default-route` attach through `wantedBy` + `partOf`, so they reload after
every WAN flap.

### Traffic shaping

CAKE and the `wan-ifb` network configuration remain specific to `stream`. The shared IFB netdev
exists here but has no matching `.network` file to trigger the ingress-mirroring rule. The source
enables the shared `networkd-dispatcher` for RSTP setup.

## Platform

### Virtual machine and network attachment

The router's ordinary networks sit above the `lan` RSTP bridge. Its preferred port, `lan-dave`, is
an unfiltered ConnectX-4 VF trunk; `lan-jim` is the 1G `river-jim-tap` macvtap exported by
`palace`. Native `core`, the client VLANs and Digiweb VLANs 10/140 use `dave` normally and fail
over to `jim`. The shared policy is documented in [Router HA](../../networking.md#router-ha);
[failover validation](router-failover.md) covers attachment and switch outages.

The bridge uses the trunk VF's assigned MAC so the ConnectX-4's local switching can deliver
traffic from `palace` and the other VFs to the router. On `lan-hi` and `rdma-hi`, `arp_ignore=1`
and `arp_announce=2` keep router and storage addresses on their respective interfaces; otherwise
the storage VF can answer ARP for the router VIP and attract traffic to the wrong interface.

The separate ConnectX-4 VF `rdma-hi` is not a bridge port. It has a PF-applied VLAN 100 and exists
only for storage traffic.

Ordinary Ethernet traverses the guest software bridge; this does not require mlx5
switchdev or host representors. The bridge disables LRO on its ports; RDMA stays outside this
path.

### Storage

The VM's local disk holds only an ESP; `/nix` and `/persist` are LVs on `cellar`'s
`nqn.2016-06.io.spdk:river` namespace over RDMA. The initrd brings up `rdma-hi` with the dedicated
`rdma` assignment and a link-scoped host route to `cellar`, alongside `roceBootModules`.

NixOS copies the main system's `.link` units into the systemd initrd, so the `rdma-hi` rename is
shared, but its `.network` and `.netdev` units are separate. `river` therefore declares the storage
assignment and route once under `boot.initrd.systemd.network` and again under the main
`systemd.network`. The systemd initrd leaves its kernel network state in place during the stage-two
handover; `KeepConfiguration=static` on the main `.network` prevents networkd from dropping and
recreating the static address and route underneath the mounted NVMe-oF root. An installer ISO
remains attached.

## Netboot

`my.netboot.server` serves iPXE/TFTP for `sfh` and `castle` at `boot.h.nul.ie` from the `lo`
assignment, restricted to the `hi` and `lo` prefixes.

## Notable config files

- [`nixos/boxes/home/palace/vms/river.nix`](../../../nixos/boxes/home/palace/vms/river.nix) — box
  config: pppd, WAN VLANs, `wan-online.target` hooks, netboot server, NVMe-oF boot.
- [`nixos/boxes/home/routing-common/default.nix`](../../../nixos/boxes/home/routing-common/default.nix) —
  shared router definition (assignments, firewall/NAT, `as211024`).
- [`nixos/boxes/home/palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix) —
  the VM definition on `palace` (dedicated RDMA VF, trunk VF, macvtap and ESP disk).
