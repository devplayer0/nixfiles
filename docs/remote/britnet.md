# britnet

A small VPS in Birmingham (`bhx1`) acting as a second Tailscale/WireGuard egress point — a
narrower gateway role than [`britway`](britway.md) (no control plane, no BGP).

- **Source:** [`nixos/boxes/britnet.nix`](../../nixos/boxes/britnet.nix)
- **Host:** VPS (Birmingham, `bhx1`; provider uplink assignment `allhost`)
- **nixpkgs:** `mine`

## Role

- **Tailscale exit node** — logs into the headscale on [`britway`](britway.md)
  (`--login-server=https://hs.nul.ie`) with `--advertise-exit-node`.
- **WireGuard hub** — `wg0` listens on UDP 51820 on the `vpn` assignment, with a single static
  peer.
- **NAT gateway** — traffic arriving on `tailscale0`/`wg0` is forwarded out `veth0` and SNATed
  to the `allhost` v4/v6 addresses.

## Network assignments

See the consolidated [network assignments](../networking.md#box-assignments) table (this box: `britnet`).

## Platform

| Component | Allocation |
|---|---|
| Virtualisation | KVM/QEMU guest |
| Compute | 2 vCPUs and 2 GiB RAM |
| Storage | 32 GiB virtio disk with separate ext4 filesystems for `/boot`, `/nix` and `/persist`; root is tmpfs |

## Networking

- The provider interface is renamed to `veth0` by MAC. Its IPv6 default gateway sits off-subnet, so
  a link-scope route is added to reach it.
- `wg0` is a networkd WireGuard netdev keyed from `britnet/wg.key`; RA is disabled on it.
- Upstream DNS is hardcoded to Cloudflare (`1.1.1.1` / `1.0.0.1`).
- `iperf3` runs with an open port for bandwidth testing.

## Notable config files

- [`nixos/boxes/britnet.nix`](../../nixos/boxes/britnet.nix) — the whole box (single file).
