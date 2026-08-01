# waffletail

The colony Tailscale node: a subnet router and exit node that advertises the colony prefixes
into the tailnet.

- **Source:** [`shill/containers/waffletail.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/waffletail.nix)
- **Host:** NixOS container on [`shill`](../README.md)
- **nixpkgs:** `mine`

## Role

### Tailscale

The node authenticates to `hs.nul.ie` with the secret `tailscale-auth.key`. It disables Tailscale's
netfilter management, advertises itself as an exit node and advertises the colony IPv4/IPv6 ranges,
but does not accept routes. UDP port 41641 is open and forwarded here by `estuary`.

### Routing and firewall

`shill` routes the Tailscale prefixes to this container.
The repository's nftables rules trust `tailscale0`, permit colony-sourced forwarding into the
tailnet, and SNAT tailnet traffic leaving through `host0` unless its destination is already within
colony.

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `waffletail`).

Two assignments: `internal` on the `ctrs` network like the other containers, and `tailscale` for
its addresses on the tailnet itself (no DNS name).

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/waffletail.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/waffletail.nix) — container definition, Tailscale setup and forward/NAT rules
