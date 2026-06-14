# home

The home network. A VM host (`palace`), a redundant pair of routers, a storage
server, Home Assistant, and personal desktops.

- **Domain:** `h.nul.ie`
- **Source:** [`nixos/boxes/home/`](../../../nixos/boxes/home)

## Shape

```
palace (physical VM host)
├── river ──── home router (HA pair with stream)
├── cellar ── NVMe-oF storage server (SPDK)
└── sfh ───── NixOS container host ──┬── hass   (Home Assistant)
                                     └── unifi  (UniFi controller — defined, currently disabled)

stream ── standalone home router (HA pair with river)
castle ── desktop workstation (boots its disks over NVMe-oF from cellar)
```

The two routers `river` (a VM on `palace`) and `stream` (standalone hardware)
share the [`routing-common`](../../../nixos/boxes/home/routing-common) config and
form a **keepalived/VRRP high-availability pair**: DHCP (kea), router
advertisements (radvd), DNS with blocklists, NAT, and the AS211024 L2 mesh link
back to colony.

## Machines

| Machine | Role | Docs |
| --- | --- | --- |
| `palace` | Physical VM host | [palace.md](palace.md) |
| `river` | Home router (VM; VRRP pair with `stream`) | [river.md](river.md) |
| `cellar` | NVMe-oF storage server (SPDK) | [cellar.md](cellar.md) |
| `sfh` | NixOS container host | [sfh.md](sfh.md) |
| `stream` | Home router (standalone hardware; VRRP pair with `river`) | [stream.md](stream.md) |
| `castle` | Desktop workstation | [castle.md](castle.md) |

### sfh containers

| Container | Role | Docs |
| --- | --- | --- |
| `hass` | Home Assistant | [hass.md](hass.md) |
| `unifi` | UniFi network controller (defined, **currently not imported**) | [unifi.md](unifi.md) |
