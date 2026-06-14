# vaultwarden

[Vaultwarden](https://github.com/dani-garcia/vaultwarden), a Bitwarden-compatible
password manager.

- **Source:** [`shill/containers/vaultwarden.nix`](../../../nixos/boxes/colony/vms/shill/containers/vaultwarden.nix)
- **Host:** NixOS container on `shill`

## Role

- Runs Vaultwarden, fronted by `middleman` and published under `nul.ie`.

## Networking

- `internal` assignment on the `ctrs` network (alt name `vaultwarden-ctr`).
