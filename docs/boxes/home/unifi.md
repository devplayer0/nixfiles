# unifi

The UniFi network controller.

- **Source:** [`sfh/containers/unifi.nix`](../../../nixos/boxes/home/palace/vms/sfh/containers/unifi.nix)
- **Host:** NixOS container on `sfh`

## Status

> **Currently disabled.** The system is still defined (`nixos.systems.unifi`),
> but its import is commented out in
> [`sfh/containers/default.nix`](../../../nixos/boxes/home/palace/vms/sfh/containers/default.nix),
> so it is not deployed as a container right now. Re-enable by uncommenting
> `./unifi.nix` there.

## Role

- Runs the UniFi controller (`services.unifi`) to manage the home UniFi network
  gear.

## Networking

- `internal` assignment (alt name `unifi-ctr`).
