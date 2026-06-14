# gam

A game-server container (the lightweight counterpart to the OCI game servers on
`whale2`).

- **Source:** [`shill/containers/gam.nix`](../../../nixos/boxes/colony/vms/shill/containers/gam.nix)
- **Host:** NixOS container on `shill`

## Role

- Hosts game servers run directly as NixOS services — currently **Terraria**
  (config/world from secrets). Exposed to the internet via `estuary`'s port
  forwards (`:7777`).

## Networking

- `internal` assignment on the `ctrs` network (alt name `gam-ctr`).
