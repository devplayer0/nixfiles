# gam

A game-server container — the lightweight counterpart to the OCI game servers on `whale2`,
running servers directly as NixOS services. Currently it runs a single Terraria server.

- **Source:** [`shill/containers/gam.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/gam.nix)
- **Host:** NixOS container on [`shill`](../../shill.md)

## Role

- **terraria** — dedicated server (`services.terraria`): world at
  `/var/lib/terraria/NotWorld.wld`, auto-created large worlds, MOTD "sup gamers", UPnP off.
  Extra settings (e.g. password) come from the `gam/terraria.conf` age secret used as the config
  file. `openFirewall` is on, and `estuary` port-forwards TCP and UDP `7777` to this container.

## Network assignments

<!-- assignments: gam -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| gam-ctr | internal | `10.100.2.11/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::b/64` | ams1.int.nul.ie |  |
<!-- assignments-end -->

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/gam.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/gam.nix) — container definition and the Terraria service
