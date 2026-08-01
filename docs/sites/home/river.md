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
(`vlans.pon-isp`) trunked untranslated from the ONT through `brian` and `dave`; see
[switches.md](switches.md). The netdev has no L3 configuration and uses `MTUBytes=1508`, leaving a
clean `mtu`/`mru 1500` after PPPoE overhead.

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

The shared `wan-ifb` ingress-shaping pieces are inert here. CAKE is specific to `stream`, and
`networkd-dispatcher` is `mkForce false` pending scheduling tests.

## Platform

### Virtual machine and network attachment

The 100G `lan` NIC is VF 1 of `palace`'s `et100g` (MTU 9000), with every router VLAN tagged on top
as `55-lan`. A macvtap of `palace`'s 1G `et1g0` remains as the old `wan-old` path without L3
configuration. Deployments use the `hi` assignment.

### Storage

The VM's local disk holds only an ESP; `/nix` and `/persist` are LVs on `cellar`'s
`nqn.2016-06.io.spdk:river` namespace over RDMA. The initrd brings up `lan-hi`
with `roceBootModules`, and `KeepConfiguration=static` prevents networkd from dropping the address
during reconfiguration. An installer ISO remains attached.

## Netboot

`my.netboot.server` serves iPXE/TFTP for `sfh` and `castle` at `boot.h.nul.ie` from the `lo`
assignment, restricted to the `hi` and `lo` prefixes.

## Notable config files

- [`nixos/boxes/home/palace/vms/river.nix`](../../../nixos/boxes/home/palace/vms/river.nix) — box
  config: pppd, WAN VLANs, `wan-online.target` hooks, netboot server, NVMe-oF boot.
- [`nixos/boxes/home/routing-common/default.nix`](../../../nixos/boxes/home/routing-common/default.nix) —
  shared router definition (assignments, firewall/NAT, `as211024`).
- [`nixos/boxes/home/palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix) —
  the VM definition on `palace` (VF 1, macvtap, ESP disk).
