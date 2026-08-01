# qclk

A WireGuard management appliance for the `qclk` network — it terminates the `management`
tunnel and routes/NATs the `qclk` prefix. No service daemon is currently defined in the config;
the container provides the network plumbing and opens the API port.

- **Source:** [`shill/containers/qclk/`](../../../../../nixos/boxes/colony/vms/shill/containers/qclk)
  (`default.nix`)
- **Host:** NixOS container on [`shill`](../README.md)
- **nixpkgs:** `mine`

## Role

- **WireGuard `management` interface** — listens on UDP `51821` (`lib.my.c.colony.qclk.wgPort`,
  allowed through the firewall; `estuary` port-forwards it here) with the private key from the
  `qclk/wg.key` age secret. Managed devices are static peers, each pinned to its own address in the
  `qclk` prefix; the peer list currently has a single entry.
- **Routing/NAT** — `shill` routes the `qclk` prefix to this container, and outbound traffic from
  `host0` into `management` is
  SNATed to the container's `qclk` address. Forwarding into `management` is accepted from the
  AS211024 trusted IPv4 ranges (`lib.my.c.as211024.trusted.v4`).
- **API port** — TCP `8080` is accepted on the `management` interface (`apiPort`), but note
  `services = { }`: whatever serves the qclk API is not defined in this configuration today.

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `qclk`).

Two assignments: `internal` on the `ctrs` network like the other containers, and `qclk` on the
`management` WireGuard interface (IPv4 only, no DNS name).

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/qclk/default.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/qclk/default.nix) — container definition: WireGuard netdev, peer list and firewall rules
