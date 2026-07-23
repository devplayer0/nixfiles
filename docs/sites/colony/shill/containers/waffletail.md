# waffletail

The colony Tailscale node: a subnet router and exit node that advertises the colony prefixes
into the tailnet.

- **Source:** [`shill/containers/waffletail.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/waffletail.nix)
- **Host:** NixOS container on [`shill`](../../shill.md)

## Role

- **tailscale** — joins via an auth key from secrets (`tailscale-auth.key`) against the
  self-hosted Headscale control plane at `hs.nul.ie`. Runs with `--netfilter-mode=off` (firewall
  is managed by the repo's own nftables rules), `--advertise-exit-node`, and
  `--advertise-routes` covering the whole colony — `10.100.0.0/16` and `2a0e:97c0:4d2:10::/60`.
  Does **not** accept routes itself. Listens on UDP `41641` (`openFirewall`), which `estuary`
  port-forwards to this container.
- `shill` routes the Tailscale prefixes (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`) to this
  container, so colony hosts can reach tailnet clients and vice versa.
- nftables: `tailscale0` is a trusted interface; forwarding from `host0` into Tailscale is
  allowed for the colony source ranges, and tailnet-sourced traffic leaving via `host0` is
  SNATed to the container's colony addresses (except when destined to the colony ranges
  themselves).

## Network assignments

<!-- assignments: waffletail -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| waffletail-ctr | internal | `10.100.2.9/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::9/64` | ams1.int.nul.ie |  |
| waffletail | tailscale | `100.64.0.5/32` | `fd7a:115c:a1e0::5/128` | — |  |
<!-- assignments-end -->

Two assignments: `internal` on the `ctrs` network like the other containers, and `tailscale` —
its addresses on the tailnet itself (host 5 of `100.64.0.0/10` and `fd7a:115c:a1e0::/48`; no
DNS name).

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/waffletail.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/waffletail.nix) — container definition, Tailscale setup and forward/NAT rules
