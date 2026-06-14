# colony (host)

The physical dedicated server in Amsterdam and the VM host for everything in
this group.

- **Source:** [`nixos/boxes/colony/default.nix`](../../../nixos/boxes/colony/default.nix)
  (VM instances in [`nixos/boxes/colony/vms/default.nix`](../../../nixos/boxes/colony/vms/default.nix))
- **nixpkgs:** `mine-stable`

## Role

Bare-metal AMD host. It does little application work itself — its job is to run
the VMs and provide them with storage, networking and backups.

- **Virtualisation:** QEMU/KVM (`kvm-amd`, IOMMU on) via the `my.vms` module. VM
  disks are LVM logical volumes (`vm-<name>-<disk>`) in the `main` volume group;
  `estuary` additionally gets a WAN NIC by PCI passthrough.
- **Storage:** LVM-thin (`services.lvm.boot.thin`), `/persist` for state,
  `/mnt/backup` for the local borg repo. `smartd` + `rasdaemon` for health.
- **Backups:** `my.borgthin` snapshots the persist/data LVs of the host and its
  VMs into `/mnt/backup/main`, which is then `rsync`'d (along with LVM metadata)
  to rsync.net (`zh2855.rsync.net`).
- **Monitoring:** netdata (with freeipmi), smartd.

## Networking

- Two bridges: `base` (the colony "base" network, shared with `estuary`) and
  `vms` (the VM network). Dummy interfaces keep the bridges up so dependent VMs
  can start.
- Default gateway / edge is `estuary`; `colony` itself holds the `routing` and
  `internal` (a.k.a. `vm`) assignments and routes container/OCI/Tailscale
  prefixes to `shill` and `whale2`.
- `my.firewall` trusts the `vms` interface and forwards customer prefixes
  (`vm-mail`, `vm-darts`) through.

## VMs hosted here

`estuary`, `shill`, `whale2`, `git` (all NixOS, documented in this directory),
plus the non-NixOS `mail` and `darts` (see [README](README.md#non-nixos-vms)).
