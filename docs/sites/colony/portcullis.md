# portcullis

A bare-metal box destined for Nikhef, intended to take over most of the colony edge
routing currently done by the [`estuary`](estuary.md) VM.

- **Source:** [`nixos/boxes/colony/portcullis/`](../../../nixos/boxes/colony/portcullis)
- **Host:** bare metal
- **nixpkgs:** `mine-stable`

## Hardware

| Component | Inventory |
|---|---|
| Platform | Mini PC (no vendor DMI strings) |
| CPU | Intel N150 (4 cores / 4 threads) |
| Memory | 8 GiB |
| Storage | One 128 GB NVMe SSD (`nvme0n1`), partitioned as a 2 GiB ESP plus an LVM PV holding the `nix` and `persist` volumes |
| Network | Four Intel I226-V 2.5 GbE ports (`et2g5-0`…`et2g5-3`) and one dual-port Intel 82599ES 10 GbE SFP+ card (`et10g-0`, `et10g-1`) |
| Management | JetKVM (HDMI/USB KVM with virtual media) |

## Role

Not yet in service. The eventual job is to be the physical edge for the colony site at Nikhef,
taking over most of what `estuary` does today — WAN termination, firewalling and NAT, BGP for
AS211024 and DNS. Some of that functionality stays on `estuary`, and the surrounding network
topology will change with the move, so the split is not settled yet. Until it is, the config in
this repository covers only what is needed to boot and reach the box.

## Network assignments

`portcullis` has no static assignments yet. It is being staged at home before it is racked, so it
takes DHCP on the home `lo` VLAN; the colony assignments land alongside the routing config once the
topology is decided.

## Networking

- The four I226-V ports are named `et2g5-0`…`et2g5-3` and the 82599ES SFP+ ports `et10g-0` /
  `et10g-1`, pinned by permanent MAC address in `.link` files.
- Bootstrap only: a single `.network` matches every `et2g5-*` port and takes DHCP, so whichever
  port happens to be patched in brings the box up. `wait-online.anyInterface` keeps boot from
  blocking on the unpatched ports.
- kea registers the DHCP hostname, so while staged the box answers to `portcullis.dyn.h.nul.ie` —
  which is also what `my.deploy.node.hostname` points at, since there is no colony FQDN for it yet.

## Storage

A single NVMe SSD, following the usual tmpfs-root layout: a 2 GiB ESP at `/boot`, then one LVM PV
in volume group `main` carrying `portcullis-nix` (48 GiB, `/nix`) and `portcullis-persist` (the
remainder, `/persist`).

## Secrets

`my.secrets.key` is the SSH host key adopted from the installer session at install time (seeded onto
the persist volume before first boot), so secrets could be encrypted for the box without waiting for
it to come up. The box declares nothing of its own yet — only the default `user-passwd.txt` that
`my.user` brings in.

## Notable config files

- [`nixos/boxes/colony/portcullis/default.nix`](../../../nixos/boxes/colony/portcullis/default.nix) — hardware, filesystems and bootstrap networking.
