# river

One of the two home routers. `river` is a VM on `palace`; it forms a
high-availability pair with the standalone `stream`.

- **Source:** [`nixos/boxes/home/palace/vms/river.nix`](../../../nixos/boxes/home/palace/vms/river.nix),
  built from [`routing-common`](../../../nixos/boxes/home/routing-common) (instance `0`)
- **Host:** VM on `palace`
- **Deploy address:** `192.168.68.1`

## Role

Everything in [`routing-common`](../../../nixos/boxes/home/routing-common):

- **VRRP/keepalived** failover with `stream` (`keepalived.nix`) — one router is
  master at a time, sharing virtual IPs.
- **DHCP** via kea (`kea.nix`), **router advertisements** via radvd
  (`radvd.nix`).
- **DNS** (`dns.nix`) — local resolver with a blocklist
  (`dns-blocklist.txt`) and a periodic update script.
- **NAT / firewall** for the home LAN, with policy routing.
- **AS211024 L2 mesh** link back to colony/`estuary` (and the other edge
  routers), so home and colony networks interconnect.

See [stream.md](stream.md) for the other half of the pair.
