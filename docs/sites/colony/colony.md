# colony

The physical dedicated server in Amsterdam (`ams1`) and the VM host for
everything at the colony site.

- **Source:** [`nixos/boxes/colony/default.nix`](../../../nixos/boxes/colony/default.nix)
  (VM instances in [`nixos/boxes/colony/vms/default.nix`](../../../nixos/boxes/colony/vms/default.nix))
- **Host:** bare metal (this *is* the physical box)
- **nixpkgs:** `mine-stable`

## Role

Bare-metal AMD host. It does little application work itself — its job is to run
the VMs and provide them with storage, networking and backups.

- **Virtualisation:** QEMU/KVM (`kvm-amd`, IOMMU on) driven by the `my.vms`
  module: each entry in `my.vms.instances` becomes a `vm@<name>` systemd
  service running `qemu-kvm` with UEFI, a QMP/monitor socket under
  `/run/vms/<name>/`, TAP networking and optional PCI passthrough
  (`hostDevices`, bound to `vfio-pci`). `estuary` gets the WAN NIC this way.
- **Storage:** LVM-thin (`services.lvm.boot.thin`) in the `main` VG; VM disks
  are logical volumes (`vm-<name>-<disk>`, see the `lib.my.vm.disk` /
  `lvmDisk` helpers). `/persist` holds host state, `/mnt/backup` the local
  borg repo. Only the boot-critical LVs are activated in the initrd; the rest
  come up via `lvm-activate-main.service`.
- **Backups:** `my.borgthin` job `main` snapshots the persist/data LVs of the
  host and its VMs into `/mnt/backup/main`; `borgthin-rsync.service` then
  rsyncs the repo to rsync.net and `rsync-lvm-meta.service` ships the LVM
  metadata alongside (both run idle-priority, after the borg job).
- **Monitoring/health:** netdata (freeipmi, ignoring the VCCM sensor), `smartd`
  (logging to `/var/log/smartd`), `rasdaemon`, `fstrim` at 04:45 (before the
  05:00 backup).

## Network assignments

<!-- assignments: colony -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| colony (vm) | internal | `94.142.241.224/32` | `2a0e:97c0:4d2:10::2/64` | ams1.int.nul.ie |  |
| colony-routing | routing | `10.100.0.2/24 gw 10.100.0.1` | — | ams1.int.nul.ie |  |
| colony-vms | vms | `10.100.1.1/24` | `2a0e:97c0:4d2:11::1/64` | ams1.int.nul.ie |  |
<!-- assignments-end -->

## Networking

- Two bridges: `base` (the colony base network, shared with `estuary`) and
  `vms` (the VM network). Dummy interfaces (`base0`, `vms0`) keep the bridges
  up in networkd's eyes so dependent VMs can start.
- `colony` sends RAs on `vms` (DNS = `estuary`'s base address) and carries
  static routes for the downstream prefixes: `ctrs` via `shill`, `oci` via
  `whale2`, plus the Tailscale, `qclk` and `jam` prefixes via `shill`.
- `estuary` is the default gateway (via the `base` bridge); `colony`'s own
  public-facing address is its `internal` assignment (a `vip1` /32, alt name
  `vm`).
- The customer VMs attach to dedicated TAP devices (`vm-mail`, `vm-darts`)
  which are **not** bridged: networkd puts the point-to-point /32
  (`lib.my.c.colony.custRouting`) and the customer's IPv6 /64 on each, sends
  RAs, and link-routes the customer's public /32 down the tap.
- `my.firewall` trusts the `vms` bridge, DNATs the shared
  `lib.my.c.colony.firewallForwards` list for traffic addressed to `estuary`'s
  public IP (so the port forwards also work from inside), and forwards the
  customer prefixes through with minimal filtering ("trust for now").

## VMs

Declared in `my.vms.instances` (`cpus`/`threads` are QEMU `smp` values):

| VM | Cores | Threads | Memory | MAC | Disks |
|---|---|---|---|---|---|
| `estuary` | 2 | 2 | 3 GiB | `52:54:00:15:1a:53` (`base`) | `esp` / `nix` / `persist` LVs + WAN NIC passthrough |
| `shill` | 12 | 2 | 40 GiB | `52:54:00:27:3d:5c` (`vms`) | `esp` / `nix` / `persist` + `media` / `minio` / `nix-cache` / `jam` LVs |
| `whale2` | 8 | 2 | 16 GiB | `52:54:00:d5:d9:c6` (`vms`) | `esp` / `nix` / `persist` + `oci` LV |
| `git` | 12 | 2 | 40 GiB | `52:54:00:75:78:a8` (`vms`) | `esp` / `nix` / `persist` / `oci` + `git` / `gitea-actions-cache` LVs |
| `mail` | 3 | 2 | 6 GiB | `52:54:00:a8:d1:03` (`vm-mail` tap) | `root` / `data` LVs |
| `darts` | 4 | 2 | 16 GiB | `52:54:00:a8:29:cd` (`vm-darts` tap) | `root` LV + `darts-media` / `darts-ext` LVs |

`estuary`, `shill`, `whale2` and `git` are NixOS systems with their own pages
(see the [README](README.md#machines)); `mail` and `darts` are not (see
[Non-NixOS VMs](README.md#non-nixos-vms)).

## Notable config files

- [`nixos/boxes/colony/default.nix`](../../../nixos/boxes/colony/default.nix) — host hardware, networkd, firewall, backups.
- [`nixos/boxes/colony/vms/default.nix`](../../../nixos/boxes/colony/vms/default.nix) — `my.vms.instances` for all six VMs.
- [`nixos/modules/vms.nix`](../../../nixos/modules/vms.nix) — the `my.vms` module itself.
