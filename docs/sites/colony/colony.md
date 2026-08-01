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

### Virtualisation

The `my.vms` module drives QEMU/KVM with `kvm-amd` and IOMMU enabled. Each `my.vms.instances` entry
becomes a `vm@<name>` systemd service with UEFI, QMP/monitor sockets under `/run/vms/<name>/`, TAP
networking and optional `hostDevices` passthrough through `vfio-pci`. `estuary` receives the WAN NIC
this way.

### Storage

All three NVMe SSDs and all four SATA HDDs are physical volumes in one `main` VG. Separate pools
and standalone RAID LVs keep workloads on the appropriate media:

| Layer | Physical layout | Main consumers |
|---|---|---|
| `nvme-tpool` | Thin-pool data is RAID 0 across the three NVMe SSDs; thin metadata is RAID 1 on two of them. The data itself has no redundancy. | Host `/nix` and `/persist`; VM system and persistence disks; fast data LVs such as `minio`, `oci`, `git`, `gitea-actions-cache`, `nix-cache` and `jam` |
| `hdds-tpool` | Thin-pool data is RAID 5 across the three 12 TB HDDs; thin metadata is RAID 1 on two NVMe SSDs. | `media`, passed to `shill`, and `backup`, mounted by the host at `/mnt/backup` |
| `darts-media` | Standalone RAID 5 LV spanning all four HDDs. | Bulk storage passed to `darts` |
| `darts-ext` | Standalone linear LV using the remaining capacity of the 18 TB HDD. | Expansion storage passed to `darts` |

`media` and `backup` are thin-provisioned, so their virtual capacities are not additive physical
capacity and overcommit `hdds-tpool`. VM disks built with `lib.my.vm.disk` are named
`vm-<name>-<disk>` in `main`; `lib.my.vm.lvmDisk` attaches the named data LVs.

The initrd activates only `colony-nix` and `colony-persist`. This avoids checking and activating all
of the storage before switching root; `lvm-activate-main.service` activates the remaining LVs before
local filesystems and VMs need them.

### Backups

`my.borgthin` job `main` snapshots host and VM persistence/data LVs into `/mnt/backup/main`.
`borgthin-rsync.service` copies the repository to rsync.net and `rsync-lvm-meta.service` sends the
LVM metadata; both run at idle priority after the Borg job.

### Monitoring

Netdata uses FreeIPMI while ignoring the VCCM sensor. The box also runs `smartd` with logs under
`/var/log/smartd`, `rasdaemon`, and `fstrim` before the backup job.

## Network assignments

See the consolidated [network assignments](../../networking.md#box-assignments) table (this box: `colony`).

## Hardware

| Component | Inventory |
|---|---|
| Platform | ASRock Rack X570D4U server board |
| CPU | AMD Ryzen 9 5950X (16 cores / 32 threads) |
| Memory | 128 GiB |
| NVMe storage | Three 2 TB Samsung SSD 980 PRO devices providing the NVMe-backed LVM thin pool and data LVs |
| Bulk storage | Three 12 TB WD120EDBZ disks and one 18 TB WD180EDGZ disk for the bulk LVM volumes |
| Boot | SanDisk USB device holding the EFI system partition |
| Network / management | Two Intel I210 Gigabit Ethernet controllers, one passed through to `estuary`; ASPEED BMC graphics and console |

## Networking

- Two bridges: `base` (the colony base network, shared with `estuary`) and
  `vms` (the VM network). Dummy interfaces (`base0`, `vms0`) keep the bridges
  up in networkd's eyes so dependent VMs can start.
- `colony` sends RAs on `vms` (DNS = `estuary`'s base address) and carries
  static routes for the downstream prefixes: `ctrs` via `shill`, `oci` via
  `whale2`, plus the Tailscale, `qclk` and `jam` prefixes via `shill`.
- `estuary` is the default gateway (via the `base` bridge); `colony`'s own public-facing address is
  its `internal` assignment (alt name `vm`).
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

| VM | Cores | Threads | Memory | Network | Disks |
|---|---|---|---|---|---|
| `estuary` | 2 | 2 | 3 GiB | `base` | `esp` / `nix` / `persist` LVs + WAN NIC passthrough |
| `shill` | 12 | 2 | 40 GiB | `vms` | `esp` / `nix` / `persist` + `media` / `minio` / `nix-cache` / `jam` LVs |
| `whale2` | 8 | 2 | 16 GiB | `vms` | `esp` / `nix` / `persist` + `oci` LV |
| `git` | 12 | 2 | 40 GiB | `vms` | `esp` / `nix` / `persist` / `oci` + `git` / `gitea-actions-cache` LVs |
| `mail` | 3 | 2 | 6 GiB | `vm-mail` tap | `root` / `data` LVs |
| `darts` | 4 | 2 | 16 GiB | `vm-darts` tap | `root` LV + `darts-media` / `darts-ext` LVs |

`estuary`, `shill`, `whale2` and `git` are NixOS systems with their own pages
(see the [README](README.md#boxes)); [`mail`](mail.md) and [`darts`](darts.md) have host-side
definitions here, but their guest operating systems are managed out of band.

## Notable config files

- [`nixos/boxes/colony/default.nix`](../../../nixos/boxes/colony/default.nix) — host hardware, networkd, firewall, backups.
- [`nixos/boxes/colony/vms/default.nix`](../../../nixos/boxes/colony/vms/default.nix) — `my.vms.instances` for all six VMs.
- [`nixos/modules/vms.nix`](../../../nixos/modules/vms.nix) — the `my.vms` module itself.
