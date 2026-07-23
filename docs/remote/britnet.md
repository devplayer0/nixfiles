# britnet

A small VPS in Birmingham (`bhx1`) acting as a second Tailscale/WireGuard egress point — a
narrower gateway role than [`britway`](britway.md) (no control plane, no BGP).

- **Source:** [`nixos/boxes/britnet.nix`](../../nixos/boxes/britnet.nix)
- **Host:** VPS (Birmingham, `bhx1`; provider uplink assignment `allhost`)

## Role

- **Tailscale exit node** — logs into the headscale on [`britway`](britway.md)
  (`--login-server=https://hs.nul.ie`) with `--advertise-exit-node`.
- **WireGuard hub** — `wg0` listens on UDP 51820 on the `vpn` network
  (`10.200.0.0/24` / `fdfb:5ebf:6e84::/64`), with a single peer at `10.200.0.10` /
  `fdfb:5ebf:6e84::10`.
- **NAT gateway** — traffic arriving on `tailscale0`/`wg0` is forwarded out `veth0` and SNATed
  to the `allhost` v4/v6 addresses.

## Network assignments

<!-- assignments: britnet -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| britnet | allhost | `77.74.199.67/24 gw 77.74.199.1` | `2a12:ab46:5344:99::a/64 gw 2a12:ab46:5344::1` | bhx1.int.nul.ie |  |
| britnet | vpn | `10.200.0.1/24` | `fdfb:5ebf:6e84::1/64` | — |  |
<!-- assignments-end -->

## Networking

- The provider interface is renamed to `veth0` by MAC. The v6 default gateway
  (`2a12:ab46:5344::1`) sits off-subnet, so a link-scope route is added to reach it.
- `wg0` is a networkd WireGuard netdev keyed from `britnet/wg.key`; RA is disabled on it.
- Upstream DNS is hardcoded to Cloudflare (`1.1.1.1` / `1.0.0.1`).
- `iperf3` runs with an open port for bandwidth testing.

## Notable config files

- [`nixos/boxes/britnet.nix`](../../nixos/boxes/britnet.nix) — the whole box (single file).
