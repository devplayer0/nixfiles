# stream

The secondary home router. A physical Intel box, built from `routing-common` at index 1; its WAN
is a DHCP lease from the Virgin Media cable modem, and it is dual-homed to both switches.

- **Source:** [`nixos/boxes/home/stream.nix`](../../../nixos/boxes/home/stream.nix) (shared router
  config: [`routing-common`](../../../nixos/boxes/home/routing-common), index 1)
- **Host:** physical

## Role

- Backup of the router pair: `routing-common` index 1 → keepalived starts `BACKUP` (priority
  254), kea serves the upper-half DHCP pools, the zone's `ns2` points here. Takes over all VIPs
  when [`river`](river.md) is down — see [README.md](README.md#router-vips).
- Runs the same `routing-common` services as river: keepalived/VRRP, PowerDNS recursor +
  authoritative, kea DHCP + DDNS, radvd, NAT/firewall, the `as211024` L2 mesh, `iperf3`, `nginx`.
- Intel box (`kvm-intel`, `intel_iommu=on`, microcode updates).
- `octoprint` and `mjpg-streamer` (3D-printer services) are defined but **disabled**
  (`enable = false`).
- `my.deploy.node.hostname` is currently commented out (it was `192.168.68.2`).

## Network assignments

<!-- assignments: stream -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| stream | as211024 | `10.100.50.3/24` | `2a0e:97c0:4df:0:1::2/64 gw 2a0e:97c0:4df:0:2::1` | — |  |
| stream-core | core | `192.168.64.2/24` | — | h.nul.ie |  |
| stream-hi | hi | `192.168.68.2/22` | `2a0e:97c0:4d0:1::2/64` | h.nul.ie |  |
| stream-lo | lo | `192.168.72.2/21` | `2a0e:97c0:4d0:2::2/64` | h.nul.ie |  |
| stream-ut | untrusted | `192.168.80.2/24` | `2a0e:97c0:4d0:3::2/64` | h.nul.ie |  |
<!-- assignments-end -->

## WAN (Virgin Media DHCP)

- `wan` is a renamed igc NIC (`00:f0:cb:ee:ca:dd`) towards the cable modem. The modem segment is
  switch **VLAN 130** — tagging is handled on the switch (`jim`), so the box interface itself is
  untagged. The fabric side is in [switches.md](switches.md).
- `DHCP=ipv4` pulls the public lease; `dhcpV4Config.UseDNS=false` and the interface DNS points at
  the local recursor. `IPv6AcceptRA=false` — this is an IPv4-only WAN (public IPv6 arrives over
  the tunnel, not this link).
- A **static modem-management address** (`192.168.0.100/24`, host `.100` of `prefixes.modem.v4`)
  sits on `wan` alongside the DHCP lease so the modem's web UI stays reachable; it has no
  gateway.
- **`wan-online.target`** wiring: `wan-wait-online.service` (a oneshot) polls until the DHCP
  default route exists, and the target `requires`/`after`s it (`wantedBy multi-user.target`).
  The route — not networkd's wait-online — is the gate because the permanent static modem address
  would otherwise report "online" before the public lease arrives, letting `ipsec` start
  unoriented (`left=` is the public IP) and never connect.
- **CAKE QoS**: egress is shaped at the `wan` root qdisc (`Bandwidth=48M`); ingress is redirected
  by `tc` (`mirred`, installed by the `networkd-dispatcher` rule in `routing-common`) into the
  `wan-ifb` IFB at `Bandwidth=490M` with the DOCSIS overhead preset.

### Modem specifics (de-shared from `routing-common`)

The modem's management subnet shares the `wan` interface, which `routing-common` itself knows
nothing about — it declares two per-box options
([`routing-common/default.nix`](../../../nixos/boxes/home/routing-common/default.nix)) that this
box sets:

- `my.homeRouter.dns.wanSkipBroadcasts = [ 192.168.0.255 ]` — skip the modem subnet when
  auto-selecting the router's own `wan` A record for the zone's LUA record.
- `my.homeRouter.firewall.untrustedRejectV4 = [ 192.168.0.0/24 ]` — reject untrusted clients from
  reaching the modem subnet (needed only because it shares `wan`; WAN egress is otherwise
  accepted).

## Switching (STP)

`stream` is dual-homed to both switches: `lan-jim` (igc) and `lan-dave` (mlx4_en), both MTU 9000,
are enslaved to the `lan` bridge with `STP=true`. [`routing-common/mstpd.nix`](../../../nixos/boxes/home/routing-common/mstpd.nix)
runs a patched `mstpd` and forces RSTP on `lan` once it's routable, so exactly one uplink carries
traffic at a time. (The remaining NICs are renamed `et2`/`et5` and left unconfigured.)

## Notable config files

- [`nixos/boxes/home/stream.nix`](../../../nixos/boxes/home/stream.nix) — box config: DHCP WAN,
  modem management, CAKE, `wan-online.target` gate, STP bridge.
- [`nixos/boxes/home/routing-common/default.nix`](../../../nixos/boxes/home/routing-common/default.nix) —
  shared router definition (index 1).
- [`nixos/boxes/home/routing-common/mstpd.nix`](../../../nixos/boxes/home/routing-common/mstpd.nix) —
  RSTP on the `lan` bridge.
