# estuary

The colony edge router and firewall — the box that holds colony's public IPs
and connects everything else at the site to the internet.

- **Source:** [`nixos/boxes/colony/vms/estuary/`](../../../nixos/boxes/colony/vms/estuary)
  (`default.nix`, `bgp.nix`, `dns.nix`, `bandwidth.nix`)
- **Host:** VM on `colony` (gets the WAN NIC by PCI passthrough)
- **nixpkgs:** `mine`

## Role

- **Edge routing / firewall / NAT** — owns the colony public IPv4/IPv6 assignments, NATs outbound
  traffic, and port-forwards inbound services (see [Firewall and NAT](#firewall-and-nat)).
- **DNS** — PowerDNS authoritative server *and* recursor (see [DNS](#dns)).
- **BGP** — BIRD2 speaking AS211024 with upstreams, IXP route servers and
  direct peers (see [BGP](#bgp)).
- **VPNs** — the `as211024` L2 VXLAN mesh plus three point-to-point WireGuard
  tunnels (see [VPNs](#vpns)).
- **Misc** — `iperf3` server, netdata.

## Network assignments

See the consolidated [network assignments](../../networking.md#box-assignments) table (this box: `estuary`).

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

`my.firewall` (nftables). Inbound port forwards (`my.firewall.nat.forwardPorts`,
driven by the shared `lib.my.c.colony.firewallForwards` list):

| Service | Forwarded to |
|---|---|
| HTTP/S, Matrix federation | `middleman` |
| Git | `git` |
| Game servers | OCI servers on `whale2`, `gam` |
| Tailscale | `waffletail` |
| `qclk` WireGuard | `qclk` |

Besides the forwards, `extraRules` defines:

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

Both halves are PowerDNS ([`dns.nix`](../../../nixos/boxes/colony/vms/estuary/dns.nix)). The live
forward and reverse records are listed in the generated [DNS reference](../../reference/dns.md).

### Authoritative

`my.pdns.auth`, listening on `0.0.0.0:5353` / `[::]:5353`. Primary for
`ams1.int.nul.ie`, `100.10.in-addr.arpa` and the `2a0e:97c0:4d2::/48` reverse
zone.

- Zone contents are largely generated from `allAssignments`
  (`lib.my.dns.fwdRecords` / `ptrRecords` / `ptr6Records`); `ALIAS` records
  (with `expand-alias`) point the zone apex at estuary itself.
- AXFR is allowed to HE.net's secondary and the trusted internal/site-egress sources used by the
  generated DNS reference.
- `_acme-challenge` is a LUA `TXT` record answered from a file (DNS-01 issuance).
- Reached publicly via the NAT redirect of port 53 → 5353; the `base` side also
  accepts DNS directly.

### Recursor

`my.pdns.recursor` (`pdns-recursor`), listening on localhost and the `base`
addresses, serving `prefixes.all` and the Tailscale prefixes.

- Authoritative zones are forwarded back to `127.0.0.1:5353` (with NOTIFY
  support, so changes show up immediately).
- A small Lua `preresolve` hook rewrites `nix-cache.nul.ie` →
  `http.ams1.int.nul.ie` so cache traffic stays on-site.

## BGP

BIRD2 ([`bgp.nix`](../../../nixos/boxes/colony/vms/estuary/bgp.nix)) speaking **AS211024**:

| Peer | ASN | Role | Where / notes |
|---|---|---|---|
| ColoClue | AS8283 | Upstream | `euNetworks` 2/3, v4+v6 |
| iFog | AS34927 | Upstream | IPv6 transit |
| Hurricane Electric | AS6939 | Upstream | IPv6 over Frys-IX |
| Frys-IX | AS56393 | IXP route server | |
| NL-ix | AS34307 | IXP route server | lower preference |
| FogIXP | AS47498 | IXP route server | |
| LUJE.net | AS212855 | Direct peer | ColoClue/Frys-IX/FogIXP + multihop labs |
| jurrian | AS212635 | Direct peer | |
| Meta | AS32934 | Direct peer | Frys-IX/NL-ix |
| Cloudflare | AS13335 | Direct peer | Frys-IX |
| Apple | AS714 | Direct peer | NL-ix |
| HE | AS6939 | Direct peer | Frys-IX (v4) |
| bgp.tools | AS212232 | Monitoring | multihop collector, `add paths` |

Statics originate the site prefixes: the `vip*` ranges via `base`, the
ams1/internal v6 prefixes via `base`/`as211024`, and the home /48 towards the
home routers' `as211024` VIP.

Currently disabled (commented out): efero transit over FogIXP ("not working so
well lately") and the NL-ix Cloudflare sessions.

## VPNs

### `as211024` L2 mesh

Member alongside `river`/`stream`/`britway` (`my.vpns.l2`, the `l2mesh` module).
The mesh transport, crypto and addressing are shared fabric — see
[The AS211024 L2 mesh](../../networking.md#the-as211024-l2-mesh) in networking.md.

### WireGuard tunnels

Point-to-point tunnels terminated here as networkd `wireguard` netdevs (private
keys from agenix); each SNATs out its own interface address:

| Tunnel | Port | Prefix | Notes |
|---|---|---|---|
| `kelder` | 51820 | — | to the remote `kelder` site; kelder's public `estuary` assignment is routed over the tunnel |
| `hillcrest` | 51822 | `prefixes.hillcrest.v4` (`10.100.5.0/30`) | /32 pair, estuary `.1` ↔ remote `.2` |
| `john-valorant` | 51823 | `prefixes.john-valorant.v4` (`10.100.5.4/30`) | /32 pair, estuary `.1` ↔ remote `.2` |

## Bandwidth management

[`bandwidth.nix`](../../../nixos/boxes/colony/vms/estuary/bandwidth.nix) implements a WAN shaper: a
token-bucket filter on `wan` (outbound) and on an `ifb-wan` IFB device that ingress traffic is
mirrored into (inbound), with
[`bandwidth.py`](../../../nixos/boxes/colony/vms/estuary/bandwidth.py) as a `bandwidth-limiter`
service that watches utilisation and can adjust the configured rate. **Currently disabled** — the
file is not in estuary's `imports` (only `dns.nix` and `bgp.nix` are), so no shaping is applied.

## Notable config files

- [`nixos/boxes/colony/vms/estuary/default.nix`](../../../nixos/boxes/colony/vms/estuary/default.nix) — system, networkd, firewall, WireGuard, mesh membership.
- [`nixos/boxes/colony/vms/estuary/bgp.nix`](../../../nixos/boxes/colony/vms/estuary/bgp.nix) — BIRD2 config.
- [`nixos/boxes/colony/vms/estuary/dns.nix`](../../../nixos/boxes/colony/vms/estuary/dns.nix) — PowerDNS auth + recursor.
- [`nixos/boxes/colony/vms/estuary/bandwidth.nix`](../../../nixos/boxes/colony/vms/estuary/bandwidth.nix) — WAN shaper (disabled, not imported).
