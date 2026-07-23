# qclk

A WireGuard management appliance for the `qclk` network — it terminates the `management`
tunnel and routes/NATs the `qclk` prefix. No service daemon is currently defined in the config;
the container provides the network plumbing and opens the API port.

- **Source:** [`shill/containers/qclk/`](../../../../../nixos/boxes/colony/vms/shill/containers/qclk)
  (`default.nix`)
- **Host:** NixOS container on [`shill`](../../shill.md)

## Role

- **WireGuard `management` interface** — listens on UDP `51821` (`lib.my.c.colony.qclk.wgPort`,
  allowed through the firewall; `estuary` port-forwards it here) with the private key from the
  `qclk/wg.key` age secret. Managed devices are static peers, each pinned to its own address in
  the `qclk` prefix (`10.100.4.0/24`); the peer list currently has a single entry (host 2).
- **Routing/NAT** — the container itself is host 1 of the `qclk` prefix. `shill` routes
  `10.100.4.0/24` to this container, and outbound traffic from `host0` into `management` is
  SNATed to the container's `qclk` address. Forwarding into `management` is accepted from the
  AS211024 trusted IPv4 ranges (`lib.my.c.as211024.trusted.v4`).
- **API port** — TCP `8080` is accepted on the `management` interface (`apiPort`), but note
  `services = { }`: whatever serves the qclk API is not defined in this configuration today.

## Network assignments

<!-- assignments: qclk -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| qclk-ctr | internal | `10.100.2.10/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::a/64` | ams1.int.nul.ie |  |
| qclk | qclk | `10.100.4.1/24` | — | — |  |
<!-- assignments-end -->

Two assignments: `internal` on the `ctrs` network like the other containers, and `qclk` — host 1
of the `qclk` prefix on the `management` WireGuard interface (IPv4 only, no DNS name).

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/qclk/default.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/qclk/default.nix) — container definition: WireGuard netdev, peer list and firewall rules
