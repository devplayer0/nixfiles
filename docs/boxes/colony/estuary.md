# estuary

The colony edge router and firewall — the machine that holds colony's public
IPs and connects everything else to the internet.

- **Source:** [`nixos/boxes/colony/vms/estuary/`](../../../nixos/boxes/colony/vms/estuary)
  (`default.nix`, `bgp.nix`, `dns.nix`, `bandwidth.nix`)
- **nixpkgs:** `mine`
- **Host:** VM on `colony` (gets the WAN NIC by PCI passthrough)

## Role

- **Edge routing / firewall / NAT:** owns the colony public IPv4/IPv6
  (`94.142.241.x` / `2a02:898:0:20::`), does NAT and port-forwarding for the
  internal services (`my.firewall.nat.forwardPorts` driven by
  `firewallForwards`). Forwards HTTP/S to `middleman`, git to `git`, game ports
  to the OCI game servers on `whale2`, etc.
- **BGP:** runs BIRD2 ([`bgp.nix`](../../../nixos/boxes/colony/vms/estuary/bgp.nix))
  announcing AS211024, over VLANs on the WAN link:
  - peers at the IXPs **Frys-IX**, **NL-ix** and **FogIXP**;
  - plus **iFog transit** (`ifog-transit`) — an upstream transit provider from
    iFog, **not** an IXP.
- **DNS:** authoritative/recursive DNS ([`dns.nix`](../../../nixos/boxes/colony/vms/estuary/dns.nix)),
  redirected to port 5353 locally.
- **VPNs:**
  - Part of the AS211024 **L2 VXLAN mesh** (`my.vpns.l2`) with `river`, `stream`
    and `britway`.
  - WireGuard endpoints for the remote `kelder` site, `hillcrest`, and
    `john-valorant`.
- **Misc:** iperf3 server. (A bandwidth-accounting script,
  [`bandwidth.py`](../../../nixos/boxes/colony/vms/estuary/bandwidth.py), exists but
  is **legacy and not currently used**.)

## Networking

- `wan` — the passed-through igb NIC (9000 MTU), carrying the upstream uplink and
  tagged IXP VLANs (`ifog` 409 → `frys-ix`/`nl-ix`/`fogixp`/`ifog-transit`).
- `base` — colony base network; sends RAs and provides DNS to the base prefix,
  routes the VM/container/OCI/Tailscale prefixes back to `colony`.
- `as211024` — the L2 mesh interface.
- Assignments: `internal` (public, alt name `fw`), `base`, `as211024`.
