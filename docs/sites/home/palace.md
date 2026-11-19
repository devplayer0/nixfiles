# palace

The physical VM host for the home site. Runs the `river`, `cellar`, `sfh` and `slop-cannon` VMs and
feeds them SR-IOV VFs, PCI NVMe drives, LVM disks and an NVMe-oF disk.

- **Source:** [`nixos/boxes/home/palace/default.nix`](../../../nixos/boxes/home/palace/default.nix)
  (VM definitions in [`palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix))
- **Host:** physical
- **nixpkgs:** `mine-stable`

## Hardware

| Component | Inventory |
|---|---|
| Platform | Gigabyte X399 DESIGNARE EX |
| CPU | AMD Ryzen Threadripper 1950X (16 cores / 32 threads) |
| Memory | 128 GiB |
| Host storage | 500 GB Samsung SSD 860 EVO containing the EFI partition and the `main` LVM thin pool |
| Bulk storage | Three 8 TB Seagate IronWolf disks in the `hdds` VG, providing the RAID-backed `hdd-storage` and `frigate` LVs |
| NVMe storage | Three 2 TB Samsung NVMe devices passed through to `cellar`; SPDK combines them as the `NVMeRaid` RAID 0 device |
| Network / graphics | Mellanox ConnectX-4 100G adapter using SR-IOV, two Intel I211 Gigabit Ethernet controllers (the only BASE-T NICs), and an AMD Radeon RX 550/560-family GPU |

## Role

- Home hypervisor: VMs are declared in `my.vms.instances`
  ([`palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix)); disks are LVs in
  the `main` thin pool (`services.lvm.boot.thin.enable`).
- AMD box (`kvm-amd`, `amd_iommu=on`, microcode updates); the kernel is built with
  `ACPI_APEI_PCIEAER`/`PCIEAER` for the PCIe passthrough work below.
- Runs [`slop-broker`](../../slop-broker.md) for `slop-cannon`'s agents (see
  [below](#slop-broker)).

## Network assignments

See the consolidated [network assignments](../../networking.md#box-assignments) table (this box: `palace`).

## Networking

100G `uplink-dave` (mlx5, MTU 9000) connects to the `dave` switch and carries `lan-hi` (VLAN 100,
the `hi` assignment). A udev rule creates six SR-IOV VFs on the PF. Two physically separate Intel
connections lead to `jim`: `host-jim` serves `palace` and `sfh`, while `river-jim-phy` is exported
exclusively to `river`.

- `lan-core` is a bridge with the `core` assignment (no gateway); the 1G `host-jim` connection and
  the `lan-lo-phy` VLAN ride on it. `lan-lo` is a second, L3-less bridge used for VM netboot and
  `lo` clients.
- The separate 1G `river-jim-phy` connection is exported exclusively to `river` as the
  passthru-mode macvtap `river-jim-tap`; the guest names it `lan-jim`. Direct PCI passthrough is
  blocked by its shared X399 IOMMU group; see [PCI isolation](#pci-isolation).

### PCI isolation

The Intel I211 controllers at `04:00.0` (`river-jim-phy`) and `06:00.0` (`host-jim`) share IOMMU
group 13 with chipset USB/SATA controllers, PCIe bridges and the wireless controller. Passing
only the router NIC through VFIO would leave the group nonviable; detaching the whole group
would remove essential host devices. The dedicated passthru-mode macvtap keeps the NIC host-owned.
Direct passthrough would need a NIC or firmware layout that isolates the controller.

Keep both Intel connections: `host-jim` provides independent host management and VM netboot,
while `river-jim-phy` carries the router's redundant trunk. The host physical router interface and
its macvtap both use `hiMTU`; the macvtap enables all-multicast reception so guest RSTP can receive
BPDUs without a guest-to-host receive-filter synchronization service.

### End-to-end interface topology

```text
dave
└─ palace uplink-dave (ConnectX-4 PF)
   ├─ VLAN 100 ───────────────────────────────> palace lan-hi ───> cellar NVMe/RDMA (slop-cannon's disk)
   ├─ VF 0  cellar-hi ────────────────────────> cellar lan-hi
   ├─ VF 1  river-rdma ───────────────────────> river rdma-hi ──> cellar NVMe/RDMA
   ├─ VF 2  sfh-hi ───────────────────────────> sfh lan-hi ─────> cellar NVMe/RDMA
   ├─ VF 3  sfh-ctrs ─────────────────────────> sfh ctrs-hi
   │                                             ├─> hass host0
   │                                             └─> unifi host0
   ├─ VF 4  river-dave ───────────────────────> river lan-dave ──┐
   └─ VF 5  slop-cannon-ut ───> slop-cannon lan-untrusted        │
                                                                 ├─> river lan (RSTP)
jim                                                              │
├─ palace river-jim-phy ── river-jim-tap ─────> river lan-jim ───┘
└─ palace host-jim ──> palace lan-core
   ├─ sfh-core-tap ───────────────────────────> sfh ctrs-core ──> unifi lan-core
   └─ VLAN 110 lan-lo-phy ──> palace lan-lo
      └─ sfh-lo-tap ──────────────────────────> sfh ctrs-lo
                                                  ├─> sfh PXE
                                                  └─> hass lan-lo
```

Inside `river`, `lan-dave` and `lan-jim` terminate on the shared `lan` RSTP bridge. `lan-core` is a
MACVLAN above it; `lan-hi`, `lan-lo` and `lan-untrusted` are VLAN uppers. `river` also adds its
Digiweb VLANs 10 and 140 to this bridge. `rdma-hi` is deliberately outside it.

VF 4 explicitly enables trust and disables MAC spoof checking for bridge traffic, which can use
MACs other than the VF's assigned address. Its automatic link state follows the physical port;
the storage VFs retain forced link state so local VF-to-VF storage can continue without carrier.
The firmware must expose enough VFs before the udev allocation can succeed.

### Interface map

The physical connections terminate on `palace`; PCI VFs and virtual interfaces hand traffic
from the host to its guests. Interface names in the destination columns belong to that box.

#### Physical connections

| Switch port | Host interface | Host networks | Guest handoff |
|---|---|---|---|
| `dave` `palace` | `uplink-dave` | VLAN 100 → `lan-hi` | Six PCI VFs, listed below |
| `jim` `palace` | `host-jim` | Native `core` → `lan-core`; VLAN 110 → `lan-lo-phy` → `lan-lo` | `sfh-core-tap` and `sfh-lo-tap` |
| `jim` `river` | `river-jim-phy` | No host L3 configuration | `river-jim-tap` macvtap → `river` `lan-jim` |

#### ConnectX-4 VFs

All six VFs belong to `uplink-dave`. VLAN filtering and carrier policy are applied on the PF.

| VF / PCI BDF | QEMU device | Guest | Guest interface | VLAN / carrier | Role |
|---|---|---|---|---|---|
| 0 / `44:00.1` | `cellar-hi` | [cellar](cellar.md) | `lan-hi` | 100 / forced up | Storage target and management |
| 1 / `44:00.2` | `river-rdma` | [river](river.md#storage) | `rdma-hi` | 100 / forced up | Dedicated NVMe/RDMA root path |
| 2 / `44:00.3` | `sfh-hi` | [sfh](sfh/README.md) | `lan-hi` | 100 / forced up | NVMe/RDMA root and management |
| 3 / `44:00.4` | `sfh-ctrs` | [sfh](sfh/README.md#networking) | `ctrs-hi` | 100 / forced up | Container `hi` network |
| 4 / `44:00.5` | `river-dave` | [river](river.md#virtual-machine-and-network-attachment) | `lan-dave` | Unfiltered trunk / automatic | Preferred RSTP attachment |
| 5 / `44:00.6` | `slop-cannon-ut` | [slop-cannon](slop-cannon.md#network) | `lan-untrusted` | 120 / automatic | Agents' only network. MAC spoof checking is on. |

#### Virtual Ethernet handoffs

| Host interface | Kind / parent | Guest interface | Downstream use |
|---|---|---|---|
| `river-jim-tap` | Passthru macvtap on `river-jim-phy` | `river` `lan-jim` | Backup RSTP attachment |
| `sfh-core-tap` | TAP on `lan-core` | `sfh` `ctrs-core` | `unifi` `lan-core` |
| `sfh-lo-tap` | TAP on `lan-lo` | `sfh` `ctrs-lo` | PXE boot; `hass` `lan-lo` |

`sfh` keeps no L3 configuration on the three `ctrs-*` parents. Its nspawn configuration creates the
container-side names shown above; `host0` remains the default `hi` interface in both containers.
See [the `sfh` page](sfh/README.md#networking) for its container-oriented view and
[failover validation](router-failover.md) for tested failure scenarios and maintenance checks.

## VMs

The RAID-backed `hdds` LVs need `dm-raid` loaded in the initrd: LVM's initial autoactivation can
run before stage-two module loading. `sfh` requires the `frigate` LV before QEMU can start.

| VM | vCPUs | RAM | Passthrough | Notes |
|---|---|---|---|---|
| `cellar` | 8c × 2t | 16 GiB | `cellar-hi` VF 0 (`44:00.1`); NVMe `41:00.0`–`43:00.0` | pinned to NUMA node 1; split IRQ chip + vIOMMU |
| `river` | 3c × 2t | 4 GiB | `river-rdma` VF 1 (`44:00.2`), `river-dave` VF 4 (`44:00.5`), `river-jim-tap` | only an ESP local disk (plus an installer ISO) — root is NVMe-oF from `cellar` |
| `sfh` | 8c × 2t | 32 GiB | `sfh-hi` VF 2 (`44:00.3`), `sfh-ctrs` VF 3 (`44:00.4`); two USB host ports | no boot disk — netboots; gets the `hdds/frigate` LV |
| `slop-cannon` | 16c × 2t | 24 GiB | `slop-cannon-ut` VF 5 (`44:00.6`) | disk is NVMe-oF from `cellar`, connected by `palace` (plus an installer ISO) |

`slop-cannon`'s vCPUs are overcommitted (the VMs total more vCPUs than the host's 32 threads) so
coding agents can burst; `vm@slop-cannon` has a low `CPUWeight`, so `cellar`, `river` and `sfh`
win under contention.

Boot ordering is enforced with systemd dependencies: `vm@river` waits for `cellar`'s SSH port (and
for the `river-jim-tap` device), and `vm@sfh` waits for `river` — storage first, then the router,
then everything that boots off both. `vm@slop-cannon` waits only for its disk (below); nothing
waits for it.

`vm@` units don't restart on deploy (`restartIfChanged = false`); a changed VM config applies the
next time the VM starts.

### `slop-cannon`'s disk

`palace` is an NVMe-oF initiator for one guest: `slop-cannon`'s disk is
`nqn.2016-06.io.spdk:slop-cannon` on [`cellar`](cellar.md), connected by `palace` (`my.nvme.uuid`
is its host NQN) and passed to QEMU as a virtio disk. The guest never speaks NVMe-oF itself:
SPDK only checks the host NQN, which root in the guest could forge.

`palace` hosts `cellar`, so the connection is kept out of `palace`'s own boot and shutdown:

- `slop-cannon-disk.service` waits for `cellar`'s SSH port, runs `nvme connect -t rdma` over
  `lan-hi` and disconnects on stop. It is `BindsTo` / `After` `vm@cellar`, and only
  `vm@slop-cannon` requires it. Nothing in the initrd, `fileSystems` or `multi-user.target` uses
  the disk.
- Shutdown runs in reverse: `vm@slop-cannon`, then the disconnect, then `cellar`.
- `--ctrl-loss-tmo 60`: if `cellar` dies, the controller is removed after a minute and QEMU sees
  I/O errors, instead of the kernel retrying forever.
- `devices/global_filter` rejects `/dev/nvme*` in `lvm.conf`, so `palace` never activates the
  guest's volume group (also called `main`). `palace` has no NVMe of its own.

## `slop-broker`

`palace` runs [`slop-broker`](../../slop-broker.md), which carries out privileged operations for
the agents on `slop-cannon` after policy and, usually, a human approve them.

- `slop-cannon` reaches it only over vsock: the VM has a `vhost-vsock-pci` device, and the broker
  identifies it by that device's CID. Policy is set per operation in
  [`palace/slop-broker.nix`](../../../nixos/boxes/home/palace/slop-broker.nix).
- The broker holds the deploy key (age secret `palace/slop-broker-deploy.key`). That key is root on
  every box, so `palace` must be treated as being as sensitive as a workstation with `.keys/`.
- Answer requests on `palace` as `dev` with `slop-approve`. In a terminal it shows each request
  in full, asks for an answer and waits for new ones; `slop-approve list` and
  `slop-approve <id> <decision>` (any unique ID prefix) work from scripts. `slop-approve log`
  shows recent requests, answers and results from the audit log
  (`/var/lib/slop-broker/audit.jsonl`, also in the journal).
- Requesters and approvers on other boxes log in over SSH as `slop`, whose keys can only run the
  broker's forced command (see
  [Other requesters and approvers](../../slop-broker.md#other-requesters-and-approvers)). The
  agents on `castle` are the requester `castle`, with the same policy as `slop-cannon`, and
  `castle` also has an approver key (`sshApprovers.castle`).

## Notable config files

- [`nixos/boxes/home/palace/default.nix`](../../../nixos/boxes/home/palace/default.nix) — host
  hardware, networkd (links/bridges/SR-IOV), LVM.
- [`nixos/boxes/home/palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix) —
  VM instances, boot ordering and `slop-cannon`'s disk connection.
- [`nixos/boxes/home/palace/slop-broker.nix`](../../../nixos/boxes/home/palace/slop-broker.nix) —
  the broker's policy for `slop-cannon`, its deploy key and the VM's vsock device.
