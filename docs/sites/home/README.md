# Home site

The home network (domain `h.nul.ie`): a redundant pair of routers in front of a VM host, an
NVMe-oF storage target, an IoT container host, and a workstation. The two routers — `river` (a VM)
and `stream` (a physical box) — are built from one shared
[`routing-common`](../../../nixos/boxes/home/routing-common) definition as an active/backup VRRP
pair, and everything clients touch (gateway, DNS) is a floating VIP that follows the master.

- **Source:** [`nixos/boxes/home/`](../../../nixos/boxes/home)

## Hierarchy

```
h.nul.ie
├── palace (physical VM host — AMD, 100G, SR-IOV)
│   ├── river ── primary router VM (PPPoE / Digiweb WAN)
│   ├── cellar ─ NVMe-oF / SPDK storage target VM
│   └── sfh ──── container host VM ("services for home")
│       ├── hass ── Home Assistant + Frigate + MQTT (container)
│       └── unifi ─ UniFi controller (container)
├── stream (physical secondary router — Virgin Media WAN)
└── castle (workstation / gaming desktop — netboot, NVMe-oF root)
```

## Machines

| Box | Role | Host | Page |
|---|---|---|---|
| `palace` | VM host | physical | [palace.md](palace.md) |
| `river` | Primary router (VRRP pair with `stream`) | VM on `palace` | [river.md](river.md) |
| `stream` | Secondary router (VRRP pair with `river`) | physical | [stream.md](stream.md) |
| `cellar` | NVMe-oF / SPDK storage target | VM on `palace` | [cellar.md](cellar.md) |
| `sfh` | NixOS container host | VM on `palace` | [sfh.md](sfh.md) |
| `castle` | Workstation / gaming desktop | physical | [castle.md](castle.md) |
| `hass` | Home Assistant + Frigate + MQTT | container on `sfh` | [sfh/containers/hass.md](sfh/containers/hass.md) |
| `unifi` | UniFi controller | container on `sfh` | [sfh/containers/unifi.md](sfh/containers/unifi.md) |

## Router VIPs

Clients never use a router's real address: `kea` (DHCP) and `radvd` (RAs) hand out the per-VLAN
floating VIPs as both gateway and DNS server, and `keepalived` moves them between `river` and
`stream`. They are declared as pseudo-systems (`router-hi` / `router-lo` / `router-ut`) in
`routing-common`'s `extraAssignments`, with addresses from `lib.my.c.home.vips`
([`lib/constants.nix`](../../../lib/constants.nix)); `pdns-recursor` binds them on both routers
(`ip_nonlocal_bind`) so DNS follows the master instead of relying on client resolver timeouts.

| Pseudo-system | Network | IPv4 | IPv6 |
|---|---|---|---|
| `router-hi` | `hi` (VLAN 100) | `192.168.71.254/22` | `2a0e:97c0:4d0:1::ffff/64` |
| `router-lo` | `lo` (VLAN 110) | `192.168.79.254/21` | `2a0e:97c0:4d0:2::ffff/64` |
| `router-ut` | `untrusted` (VLAN 120) | `192.168.80.254/24` | `2a0e:97c0:4d0:3::ffff/64` |

Notes:

- The IPv6 gateway clients learn from RAs is the link-local `fe80::1` on each VLAN (a
  `virtual_ipaddress_excluded` VIP; `radvd` advertises from it), not the global VIP above.
- `keepalived` also floats a VIP on the `as211024` mesh interface (`10.100.50.4`,
  `2a0e:97c0:4df:0:1::ffff`) — it has no pseudo-system because nothing client-facing uses it.
- The `untrusted` VLAN is an exception to "DNS follows the master": its DHCP/RA options hand out
  Cloudflare resolvers (`1.1.1.1` / `2606:4700:4700::1111`), not the VIP.

## Networks

| Network | VLAN | IPv4 | IPv6 | MTU |
|---|---|---|---|---|
| `core` | native | `192.168.64.0/24` | — | 1500 |
| `hi` | 100 | `192.168.68.0/22` | `2a0e:97c0:4d0:1::/64` | 9000 |
| `lo` | 110 | `192.168.72.0/21` | `2a0e:97c0:4d0:2::/64` | 1500 |
| `untrusted` | 120 | `192.168.80.0/24` | `2a0e:97c0:4d0:3::/64` | 1500 |
| `wan` (stream) | 130 | DHCP public lease + modem mgmt `192.168.0.0/24` | — | 1500 |
| `pon-isp` (river) | 10 | PPPoE transport (no L3) | — | 1508 |
| `wan-pon-ont` (river) | 140 | ONT mgmt `192.168.100.0/24` | — | 1500 |

The logical network map lives in [networking.md](../../networking.md).

## Switch fabric

The boxes hang off three hand-configured switches — `jim` and `dave` (MikroTik, RouterOS) and
`brian` (Ubiquiti, UniFi) — which are **not** managed by this flake. The physical topology, VLAN
map, the Digiweb WAN path (trunked VLAN 10 + PVID 140 at the ONT edge), and the multi-ONT plan are
documented in [switches.md](switches.md).
