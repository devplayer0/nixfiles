# qclk

The `qclk` service container.

- **Source:** [`shill/containers/qclk/`](../../../nixos/boxes/colony/vms/shill/containers/qclk)
- **Host:** NixOS container on `shill`

## Role

- Runs the custom `qclk` service, exposing an API that is reached over a
  dedicated WireGuard **`management`** network. Managed devices are configured as
  WireGuard peers (each gets an address in the `qclk` prefix), and AS211024
  trusted hosts are allowed to reach the API.
- `shill` routes the `qclk` prefix to this container.

## Networking

- `internal` assignment on the `ctrs` network (alt name `qclk-ctr`), plus the
  `management` WireGuard interface carrying the `qclk` prefix.

> Check `qclk/default.nix` for the current peer list and exactly what the service
> does — this entry intentionally stays high-level.
