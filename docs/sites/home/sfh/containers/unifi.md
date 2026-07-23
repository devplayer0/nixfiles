# unifi

The UniFi network controller, running as a container on [`sfh`](../../sfh.md). It manages the
home UniFi switch `brian` (see [switches.md](../../switches.md)).

- **Source:** [`nixos/boxes/home/palace/vms/sfh/containers/unifi.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/unifi.nix)
- **Host:** NixOS container on `sfh`

## Status

**Currently enabled.** The container spent a while disabled — its import was commented out of
[`containers/default.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/default.nix)
while there was no UniFi gear to manage — and was re-enabled when the UniFi switch `brian` was
added, gaining a `core` leg (`unifi-ctr-core`) at the same time so it can reach the switch on its
management network. It is imported, listed in `sfh`'s `my.containers.instances`, and
`services.unifi.enable = true`.

## Role

- **UniFi controller** (`services.unifi`, `pkgs.unifi` on `mongodb-7_0`, firewall open; TCP 8443
  allowed).
- Not a deploy-rs target (`my.deploy.enable = false`) — it's rendered via `my.asContainer` and
  started by `sfh`'s `my.containers.instances`.

## Network assignments

<!-- assignments: unifi -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| unifi-ctr-core | core | `192.168.64.21/24` | — | h.nul.ie |  |
| unifi-ctr | hi | `192.168.68.100/22 gw 192.168.71.254` | `2a0e:97c0:4d0:1::5:1/64` | h.nul.ie |  |
<!-- assignments-end -->

## Networking

Two MACVLAN legs from `sfh`'s container NICs: `host0` on `lan-hi-ctrs` (the `hi` assignment —
`unifi-ctr`, `192.168.68.100`, default gateway via the VIP) and `lan-core` on `lan-core-ctrs`
(the `core` assignment — `unifi-ctr-core`, `192.168.64.21/24`, no gateway). The `core` leg is
how the controller talks to the switches: `brian` lives at `192.168.64.13` on `core`.

## Notable config files

- [`nixos/boxes/home/palace/vms/sfh/containers/unifi.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/unifi.nix) —
  container system: UniFi service, assignments.
- [`nixos/boxes/home/palace/vms/sfh/default.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/default.nix) —
  the `sfh` side: container instance, MACVLAN wiring.
