# unifi

The UniFi network controller, running as a container on [`sfh`](../README.md). It manages the
home UniFi switch `brian` (see [switches.md](../../switches.md)).

- **Source:** [`nixos/boxes/home/palace/vms/sfh/containers/unifi.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/unifi.nix)
- **Host:** NixOS container on `sfh`
- **nixpkgs:** `mine`

## Role

- **UniFi controller** (`services.unifi`, `pkgs.unifi` on `mongodb-7_0`, firewall open; TCP 8443
  allowed).
- Not a deploy-rs target (`my.deploy.enable = false`) — it's rendered via `my.asContainer` and
  started by `sfh`'s `my.containers.instances`.

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `unifi`).

## Status

**Currently enabled.** The container spent a while disabled — its import was commented out of
[`containers/default.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/default.nix)
while there was no UniFi gear to manage — and was re-enabled when the UniFi switch `brian` was
added, gaining a `core` interface (`unifi-ctr-core`) at the same time so it can reach the switch on its
management network. It is imported, listed in `sfh`'s `my.containers.instances`, and
`services.unifi.enable = true`.

## Networking

Two MACVLAN interfaces come from `sfh`'s container NICs: `host0` on `lan-hi-ctrs` carries the `hi`
assignment (`unifi-ctr`, default gateway via the VIP), while `lan-core` on `lan-core-ctrs` carries
the gatewayless `core` assignment (`unifi-ctr-core`). The `core` interface is how the controller
talks to `brian` and the other switches on their management network.

## Notable config files

- [`nixos/boxes/home/palace/vms/sfh/containers/unifi.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/unifi.nix) —
  container system: UniFi service, assignments.
- [`nixos/boxes/home/palace/vms/sfh/default.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/default.nix) —
  the `sfh` side: container instance, MACVLAN wiring.
