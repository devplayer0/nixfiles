# gam

A game-server container currently dedicated to Terraria.

- **Source:** [`shill/containers/gam.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/gam.nix)
- **Host:** NixOS container on [`shill`](../README.md)
- **nixpkgs:** `mine`

## Role

Runs lightweight game servers directly as NixOS services, rather than as OCI containers on
[`whale2`](../../whale2.md).

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `gam`).

## Terraria server

`services.terraria` runs the dedicated server with its world at
`/var/lib/terraria/NotWorld.wld`. It creates large worlds automatically, uses the MOTD
"sup gamers", and disables UPnP. Additional settings such as the password come from the
`gam/terraria.conf` age secret used as the service configuration file.

`openFirewall` is enabled, and `estuary` forwards TCP and UDP port `7777` to the container.

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/gam.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/gam.nix) — container definition and the Terraria service
