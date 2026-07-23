# river

The primary home router. A VM on `palace`, built from `routing-common` at index 0; it runs PPPoE
to Digiweb directly on the ISP's VLAN 10 and normally holds the master side of the VRRP pair with
[`stream`](stream.md).

- **Source:** [`nixos/boxes/home/palace/vms/river.nix`](../../../nixos/boxes/home/palace/vms/river.nix)
  (shared router config: [`routing-common`](../../../nixos/boxes/home/routing-common), index 0)
- **Host:** VM on `palace`

## Role

- Primary of the router pair: `routing-common` index 0 → keepalived starts `MASTER` (priority
  255), kea serves the lower-half DHCP pools, the zone's SOA/`ns1` point here.
- Everything from `routing-common`: keepalived/VRRP ([`keepalived.nix`](../../../nixos/boxes/home/routing-common/keepalived.nix)),
  PowerDNS recursor + authoritative with a blocklist ([`dns.nix`](../../../nixos/boxes/home/routing-common/dns.nix)),
  kea DHCP + DDNS ([`kea.nix`](../../../nixos/boxes/home/routing-common/kea.nix)), radvd
  ([`radvd.nix`](../../../nixos/boxes/home/routing-common/radvd.nix)), NAT/firewall, the
  `as211024` L2 mesh link back to colony, `iperf3`, `nginx`. See
  [networking.md](../../networking.md) for the logical view and [README.md](README.md#router-vips)
  for the floating VIPs.
- **Netboot server** for `sfh` and `castle` (`my.netboot.server`): iPXE/TFTP at
  `boot.h.nul.ie` (a CNAME to `river-hi`), served from the `lo` address `192.168.72.1` and
  restricted to the hi/lo prefixes.
- **NVMe-oF client of `cellar`**: the VM's only local disk is an ESP (an installer ISO is also
  still attached); `/nix` and `/persist` are LVs on the `nqn.2016-06.io.spdk:river` namespace
  exported by `cellar` (`192.168.68.80`, RDMA).
  The initrd brings up `lan-hi` with the RoCE modules (`roceBootModules`), and
  `KeepConfiguration=static` on `lan-hi` stops networkd from dropping the NVMe-oF address on
  reconfigure.
- **SR-IOV VF passthrough**: the 100G `lan` NIC is VF 1 of palace's `et100g` (MAC
  `52:54:00:8a:8a:f2`, MTU 9000). All router VLANs — hi/lo/untrusted plus both WAN VLANs — are
  tagged on top of it (`55-lan`).
- Also carries a macvtap passthrough of palace's 1G `et1g0`, renamed `wan-old` — the pre-100G WAN
  path, kept around with no L3 config today.
- Deploy address `192.168.68.1` (`my.deploy.node.hostname`).

## Network assignments

<!-- assignments: river -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| river | as211024 | `10.100.50.2/24` | `2a0e:97c0:4df:0:1::1/64 gw 2a0e:97c0:4df:0:2::1` | — |  |
| river-core | core | `192.168.64.1/24` | — | h.nul.ie |  |
| river-hi | hi | `192.168.68.1/22` | `2a0e:97c0:4d0:1::1/64` | h.nul.ie |  |
| river-lo | lo | `192.168.72.1/21` | `2a0e:97c0:4d0:2::1/64` | h.nul.ie |  |
| river-ut | untrusted | `192.168.80.1/24` | `2a0e:97c0:4d0:3::1/64` | h.nul.ie |  |
<!-- assignments-end -->

## WAN (Digiweb PPPoE)

- `services.pppd` peer `digiweb` attaches PPPoE directly to `wan-pon-isp`
  (`plugin pppoe.so wan-pon-isp`) — the **raw ISP VLAN 10** (`vlans.pon-isp`), trunked
  untranslated from the ONT through `brian` and `dave` (the fabric side is in
  [switches.md](switches.md)). The netdev is up with no L3; `MTUBytes=1508` (baby jumbo) absorbs
  PPPoE's 8-byte overhead so the `wan` ppp interface gets a clean `mtu`/`mru 1500`.
- The Digiweb static IP (`84.203.124.128`, `elemAt routersPubV4 0`) is requested as the local
  address in IPCP. Auth is the across-all-customers shared `digiweb@nga.digiweb.ie` / `digiweb`
  (deliberately not a secret); `persist`, `maxfail 0`, 1s LCP echoes. `usepeerdns` is absent on
  purpose — Digiweb's resolvers are ignored in favour of the local recursor.
- **ONT management**: `wan-pon-ont` (VLAN 140, PVID'd at the `brian` edge) holds
  `192.168.100.100/24` so the ONT web UI at `192.168.100.1` is reachable — the `.100` mirrors
  stream's modem-management convention.
- **`wan-online.target`** is the shared "public WAN is up" gate declared by `routing-common`;
  here it is driven by the pppd hooks (`DefaultDependencies=false`, so nothing pulls it in
  early): `ip-up` installs `default dev wan scope link metric 100` and starts the target,
  `ip-down` stops it and deletes the route. Consumers (`ipsec`, `ipv6-clear-default-route`)
  attach with `wantedBy` + `partOf`, so they re-load on every WAN flap.
- The `wan-ifb` ingress-shaping pieces from `routing-common` are inert on this box: the CAKE
  config itself is stream's, and `networkd-dispatcher` (which installs the `tc` mirror) is
  `mkForce false` here pending scheduling testing.

## Notable config files

- [`nixos/boxes/home/palace/vms/river.nix`](../../../nixos/boxes/home/palace/vms/river.nix) — box
  config: pppd, WAN VLANs, `wan-online.target` hooks, netboot server, NVMe-oF boot.
- [`nixos/boxes/home/routing-common/default.nix`](../../../nixos/boxes/home/routing-common/default.nix) —
  shared router definition (assignments, firewall/NAT, `as211024`).
- [`nixos/boxes/home/palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix) —
  the VM definition on `palace` (VF 1, macvtap, ESP disk).
