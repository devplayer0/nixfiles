# britway

A Vultr VPS in London (`lon1`) acting as a network edge node: the Tailscale
control plane, an exit node, and a BGP speaker in the AS211024 mesh.

- **Source:** [`nixos/boxes/britway/`](../../../nixos/boxes/britway)
  (`default.nix`, `bgp.nix`, `nginx.nix`, `tailscale.nix`)
- **Internal domain:** `lon1.int.nul.ie`

## Role

- **Headscale** ([`tailscale.nix`](../../../nixos/boxes/britway/tailscale.nix)) — the
  self-hosted Tailscale control server (`hs.nul.ie`) the rest of the boxes log
  into.
- **Tailscale node** — advertises itself as an **exit node** and advertises the
  tailnet routes, so tailnet clients can egress / reach internal prefixes via
  britway.
- **BGP** ([`bgp.nix`](../../../nixos/boxes/britway/bgp.nix)) — part of the AS211024
  L2 VXLAN mesh (`my.vpns.l2`) alongside `estuary`, `river` and `stream`.
- **nginx** ([`nginx.nix`](../../../nixos/boxes/britway/nginx.nix)) — reverse proxy /
  web front-end with ACME certs.

## Networking

- `vultr` assignment on the provider interface; `as211024` on the mesh.
- A `veth0`/`tailscale0` setup with SNAT so tailnet traffic egresses via the VPS
  public IP.
