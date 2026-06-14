# waffletail

The colony Tailscale node / subnet router.

- **Source:** [`shill/containers/waffletail.nix`](../../../nixos/boxes/colony/vms/shill/containers/waffletail.nix)
- **Host:** NixOS container on `shill`

## Role

- Joins the Tailscale tailnet (auth key from secrets) and **advertises the colony
  prefixes** into it, acting as the subnet router so tailnet clients can reach
  colony services and vice-versa.
- nftables rules SNAT/forward between `host0` and `tailscale0` for the colony
  v4/v6 ranges. `shill` routes the Tailscale prefixes here.

## Networking

- `internal` assignment on the `ctrs` network (alt name `waffletail-ctr`); owns
  the `tailscale0` interface.
