# estuary

The colony edge router and firewall — the box that holds colony's public IPs
and connects everything else at the site to the internet.

- **Source:** [`nixos/boxes/colony/vms/estuary/`](../../../nixos/boxes/colony/vms/estuary)
  (`default.nix`, `bgp.nix`, `dns.nix`, `bandwidth.nix`)
- **Host:** VM on `colony` (gets the WAN NIC by PCI passthrough)
- **nixpkgs:** `mine`

## Role

- **Edge routing / firewall / NAT:** owns the colony public IPv4/IPv6
  (`94.142.240.44/24`, `2a02:898:0:20::329:1/64`), NATs outbound traffic, and
  port-forwards inbound services (`my.firewall.nat.forwardPorts` driven by the
  shared `lib.my.c.colony.firewallForwards` list): HTTP/S and Matrix
  federation to `middleman`, git to `git`, game ports to the OCI servers on
  `whale2` and to `gam`, Tailscale to `waffletail`, and the `qclk` WireGuard
  port.
- **DNS:** PowerDNS authoritative server *and* recursor (see below).
- **BGP:** BIRD2 speaking AS211024 with upstreams, IXP route servers and
  direct peers (see below).
- **VPNs:** member of the `as211024` L2 VXLAN mesh and endpoint for three
  point-to-point WireGuard tunnels (see below).
- **Misc:** `iperf3` server, netdata.

## Network assignments

<!-- assignments: estuary -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| estuary | as211024 | `10.100.50.1/24` | `2a0e:97c0:4df::1/64` | — |  |
| estuary-vm-base | base | `10.100.0.1/24` | `2a0e:97c0:4d2:10::1/64` | ams1.int.nul.ie |  |
| estuary-vm (fw) | internal | `94.142.240.44/24 gw 94.142.240.254` | `2a02:898:0:20::329:1/64 gw 2a02:898:0:20::1` | ams1.int.nul.ie |  |
<!-- assignments-end -->

## WAN and IXP VLANs

- `wan` — the passed-through `igb` NIC (9000 MTU, enlarged rings). It carries
  the plain upstream uplink (static v4/v6 with gateways from the `internal`
  assignment) plus the tagged `ifog` VLAN.
- `ifog` (VLAN 409) is an iFog QinQ transport that carries the IXP VLANs as
  nested tags:

| Interface | VLAN | IPv4 | IPv6 | Purpose |
|---|---|---|---|---|
| `frys-ix` | 701 | `185.1.160.196/23` | `2001:7f8:10f::3:3850:196/64` | Frys-IX peering LAN |
| `nl-ix` | 1845 | `193.239.116.145/22` | `2001:7f8:13::a521:1024:1/64` | NL-ix peering LAN |
| `fogixp` | 1147 | `185.1.147.159/24` | `2001:7f8:ca:1::159/64` | FogIXP peering LAN |
| `ifog-transit` | 702 | — | `2a0c:9a40:100f:370::2/64` | iFog IPv6 transit |

The IXP interfaces run at 1500 MTU with DHCP/RA/LLDP off; an nftables `ixp`
chain rejects non-IP/ARP ethertypes in both directions.

- `base` — colony base network; sends RAs and serves DNS to the site, and
  routes the `vms`/`ctrs`/`oci`, Tailscale, `qclk`, `vip*` and customer
  prefixes back via `colony`.
- `as211024` — the L2 mesh interface (see VPNs).

## Firewall and NAT

`my.firewall` (nftables). Besides the port forwards, `extraRules` defines:

- `routing-tcp` / `routing-udp` chains — the inbound allow-list for new
  connections from `wan`/`as211024`/IXPs towards internal services (SSH
  anywhere, otherwise per-service v4/v6 rules mirroring `firewallForwards`).
- `filter-routing` — applied to `wan`/`as211024`/IXPs → `base` forwards;
  customer prefixes (`mail`/`darts` v4, `cust.v6`) are accepted wholesale, the
  rest goes through the `routing-*` chains.
- SNAT: everything from `prefixes.all.v4` leaving non-`as211024` interfaces is
  NATed to the public IP; the WireGuard tunnel prefixes get their own SNAT
  addresses.
- DNS redirect: DNS traffic arriving at estuary's own public addresses is
  redirected to port 5353 (the authoritative server) — see below.

## DNS

Both halves are PowerDNS ([`dns.nix`](../../../nixos/boxes/colony/vms/estuary/dns.nix)):

- **Authoritative** (`my.pdns.auth`) listens on `0.0.0.0:5353` / `[::]:5353` as
  primary for `ams1.int.nul.ie`, `100.10.in-addr.arpa` and the
  `2a0e:97c0:4d2::/48` reverse zone. Zone contents are largely generated from
  `allAssignments` (`lib.my.dns.fwdRecords` / `ptrRecords` / `ptr6Records`);
  `ALIAS` records (with `expand-alias`) point the zone apex at estuary itself.
  AXFR is allowed to HE.net's secondary (`216.218.133.2` / `2001:470:600::2`),
  and `_acme-challenge` is a LUA `TXT` record answered from a file (used for
  DNS-01 issuance). Public DNS reaches it via the NAT redirect of port 53 to
  5353; the `base` side also accepts DNS directly.
- **Recursor** (`my.pdns.recursor`, `pdns-recursor`) listens on localhost and
  the `base` addresses, serving `prefixes.all` and the Tailscale prefixes. The
  authoritative zones are forwarded back to `127.0.0.1:5353` (with NOTIFY
  support so changes show up immediately), and a small Lua `preresolve` hook
  rewrites `nix-cache.nul.ie` to `http.ams1.int.nul.ie` so cache traffic stays
  on-site.

## BGP

BIRD2 ([`bgp.nix`](../../../nixos/boxes/colony/vms/estuary/bgp.nix)) speaking **AS211024**:

- **Upstreams:** ColoClue (AS8283, `euNetworks` 2/3, v4+v6); iFog IPv6 transit
  (AS34927); Hurricane Electric IPv6 over Frys-IX (AS6939).
- **IXP route servers:** Frys-IX (AS56393), NL-ix (AS34307, depref'd by 1),
  FogIXP (AS47498).
- **Direct peers:** LUJE.net (AS212855, on ColoClue/Frys-IX/FogIXP + multihop
  labs), jurrian (AS212635), Meta (AS32934, Frys-IX/NL-ix), Cloudflare
  (AS13335, Frys-IX), Apple (AS714, NL-ix), HE (AS6939, Frys-IX v4).
- **Monitoring:** a multihop session to the bgp.tools collector (AS212232)
  exporting everything with `add paths`.
- Statics originate the site prefixes: the `vip*` ranges via `base`, the
  ams1/internal v6 prefixes via `base`/`as211024`, and the home /48 towards
  the home routers' `as211024` VIP.

Currently disabled (commented out): efero transit over FogIXP ("not working so
well lately") and the NL-ix Cloudflare sessions.

## VPNs

- **`as211024` L2 mesh** (`my.vpns.l2`, the `l2mesh` module): VXLAN (VNI
  211024, UDP-encapsulated) secured with libreswan IPsec, meshing estuary with
  the home routers `river`/`stream` and `britway`. This carries the AS211024
  anycast-ish internal address space between sites.
- **WireGuard endpoints** (networkd `wireguard` netdevs, keys from agenix):
  - `kelder` — tunnel to the remote `kelder` site, port `51820`.
  - `hillcrest` — port `51822`, point-to-point /32 pair out of
    `prefixes.hillcrest.v4`.
  - `john-valorant` — port `51823`, same pattern out of
    `prefixes.john-valorant.v4`.

## Bandwidth management

[`bandwidth.nix`](../../../nixos/boxes/colony/vms/estuary/bandwidth.nix)
implements a ~95% WAN shaper: a 245 Mbit token-bucket filter on `wan`
(outbound) and on an `ifb-wan` IFB device that ingress traffic is mirrored
into (inbound), with [`bandwidth.py`](../../../nixos/boxes/colony/vms/estuary/bandwidth.py)
as a `bandwidth-limiter` service that watches/utilises the link and can adjust
the rate. **Currently disabled** — the file is not in estuary's `imports`
(only `dns.nix` and `bgp.nix` are), so no shaping is applied.

## Notable config files

- [`nixos/boxes/colony/vms/estuary/default.nix`](../../../nixos/boxes/colony/vms/estuary/default.nix) — system, networkd, firewall, WireGuard, mesh membership.
- [`nixos/boxes/colony/vms/estuary/bgp.nix`](../../../nixos/boxes/colony/vms/estuary/bgp.nix) — BIRD2 config.
- [`nixos/boxes/colony/vms/estuary/dns.nix`](../../../nixos/boxes/colony/vms/estuary/dns.nix) — PowerDNS auth + recursor.
- [`nixos/boxes/colony/vms/estuary/bandwidth.nix`](../../../nixos/boxes/colony/vms/estuary/bandwidth.nix) — WAN shaper (disabled, not imported).
