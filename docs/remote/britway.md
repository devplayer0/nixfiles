# britway

A Vultr VPS in London (`lon1`) acting as the network edge node: the self-hosted Tailscale
control plane, a tailnet exit node, and the BGP speaker for AS211024.

- **Source:** [`nixos/boxes/britway/`](../../nixos/boxes/britway)
- **Host:** VPS at Vultr (London, `lon1`)

## Role

- **Headscale** — the self-hosted Tailscale control plane at `hs.nul.ie`; every other box's
  `tailscaled` logs in here (`--login-server=https://hs.nul.ie`). Google OIDC for auth,
  SQLite state, MagicDNS under `ts.nul.ie`, and split DNS pointing the colony/home domains
  at their internal resolvers.
- **Tailscale exit node** — advertises `--advertise-exit-node` plus routes to the home v4/v6
  prefixes; tailnet traffic is SNATed out `veth0` (v4 to the Vultr public IP, v6 to the
  `as211024` mesh address).
- **BGP edge** — `bird2` speaks BGP as AS211024 to Vultr transit (AS64515, separate v4/v6
  sessions authenticated with a password from `britway/bgp-password-vultr.conf`) and exports
  everything to a `bgp.tools` monitoring session. It originates the internal, colony and home
  v6 prefixes (`2a0e:97c0:4df::/48`, `2a0e:97c0:4d2::/48`, `2a0e:97c0:4d0::/48`).
- **nginx** — reverse proxy fronting headscale (`hs.nul.ie` → `localhost` headscale port),
  with a wildcard ACME cert for `nul.ie` issued via Cloudflare DNS.

## Network assignments

<!-- assignments: britway -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| britway | as211024 | `10.100.50.5/24` | `2a0e:97c0:4df:0:2::1/64` | — |  |
| britway | vultr | `45.76.141.188/23 gw 45.76.140.1` | `2001:19f0:7402:128b::1/64` | lon1.int.nul.ie |  |
<!-- assignments-end -->

## Networking

- Two assignments: `vultr` on the provider interface `veth0` (renamed by MAC), and `as211024`
  on the l2mesh VXLAN interface (`my.vpns.l2`, a mesh shared with `estuary` and the home
  routers `river`/`stream`).
- Static routes steer colony/home v4 traffic over the `as211024` mesh. A separate `ts-extra`
  routing table (1337) with a policy rule on `tailscale0` ingress sends Tailscale-sourced v6
  traffic for colony via `estuary`, while the box's own v6 uses WAN.
- The firewall trusts the `as211024` prefixes (`lib.my.c.as211024.nftTrust`) and
  `tailscale0`; `iperf3` runs with an open port for bandwidth testing.

## Notable config files

- [`nixos/boxes/britway/default.nix`](../../nixos/boxes/britway/default.nix) — system, assignments, networkd, firewall/SNAT.
- [`nixos/boxes/britway/bgp.nix`](../../nixos/boxes/britway/bgp.nix) — `bird2` config (Vultr transit, `bgp.tools`).
- [`nixos/boxes/britway/nginx.nix`](../../nixos/boxes/britway/nginx.nix) — nginx vhosts + ACME.
- [`nixos/boxes/britway/tailscale.nix`](../../nixos/boxes/britway/tailscale.nix) — headscale + the tailnet node itself.
