# stream

One of the two home routers. `stream` is standalone hardware; it forms a
high-availability pair with `river` (a VM on `palace`).

- **Source:** [`nixos/boxes/home/stream.nix`](../../../nixos/boxes/home/stream.nix),
  built from [`routing-common`](../../../nixos/boxes/home/routing-common) (instance `1`)
- **Deploy address:** `192.168.68.2`

## Role

- Same [`routing-common`](../../../nixos/boxes/home/routing-common) role as
  [`river`](river.md): keepalived/VRRP, kea DHCP, radvd, DNS + blocklist, NAT and
  the AS211024 L2 mesh link to colony.
- Additionally pulls in `mstpd` (`routing-common/mstpd.nix`) for spanning-tree on
  its bridged ports — `stream` is the one wired into the physical switching, so
  it manages the L2 topology.

See [river.md](river.md) for the other half of the pair.
