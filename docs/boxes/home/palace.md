# palace (host)

The physical VM host for the home network — the home equivalent of `colony`.

- **Source:** [`nixos/boxes/home/palace/default.nix`](../../../nixos/boxes/home/palace/default.nix)
  (VM instances in [`palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix))

## Role

- Bare-metal host whose job is to run the home VMs via the `my.vms` module:
  `river` (router), `cellar` (storage), `sfh` (container host).
- Provides the bridged networking those VMs sit on and passes through hardware
  where needed (e.g. NVMe drives to `cellar`, NICs to `river`).

## VMs hosted here

| VM | Role | Docs |
| --- | --- | --- |
| `river` | Home router (VRRP pair with `stream`) | [river.md](river.md) |
| `cellar` | NVMe-oF storage server | [cellar.md](cellar.md) |
| `sfh` | NixOS container host (Home Assistant, …) | [sfh.md](sfh.md) |
