# britnet

A VPS in Birmingham (`bhx1`) acting as a Tailscale/WireGuard gateway node.

- **Source:** [`nixos/boxes/britnet.nix`](../../../nixos/boxes/britnet.nix)
- **Internal domain:** `bhx1.int.nul.ie`

## Role

- **Tailscale node** + **WireGuard** (`wg0`) gateway: provides a second egress /
  entry point into the boxes' overlay networks.
- nftables SNATs traffic arriving on `tailscale0` / `wg0` out of the provider
  interface (`veth0`), using the `allhost` assignment addresses.

## Networking

- Provider uplink with gateways `77.74.199.1` (v4) / `2a12:ab46:5344::1` (v6).
- `tailscale0` and `wg0` overlay interfaces; `allhost` assignment for SNAT.

> `britnet` is a separate machine from [`britway`](britway.md) — different
> provider/site, narrower role (gateway rather than control plane + BGP edge).
