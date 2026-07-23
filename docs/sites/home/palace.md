# palace

The physical VM host for the home site. Runs the `river`, `cellar` and `sfh` VMs and feeds them
SR-IOV VFs, PCI NVMe drives and LVM disks.

- **Source:** [`nixos/boxes/home/palace/default.nix`](../../../nixos/boxes/home/palace/default.nix)
  (VM definitions in [`palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix))
- **Host:** physical

## Role

- Home hypervisor: VMs are declared in `my.vms.instances`
  ([`palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix)); disks are LVs in
  the `main` thin pool (`services.lvm.boot.thin.enable`).
- AMD box (`kvm-amd`, `amd_iommu=on`, microcode updates); the kernel is built with
  `ACPI_APEI_PCIEAER`/`PCIEAER` for the PCIe passthrough work below.
- Deploy address `192.168.68.22` (`my.deploy.node.hostname`).

## Network assignments

<!-- assignments: palace -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| palace-core | core | `192.168.64.20/24` | — | h.nul.ie |  |
| palace | hi | `192.168.68.22/22 gw 192.168.71.254` | `2a0e:97c0:4d0:1::2:1/64` | h.nul.ie |  |
<!-- assignments-end -->

## Networking

- 100G `et100g` (mlx5, MTU 9000) uplinks to the `dave` switch and carries `lan-hi` (VLAN 100,
  the `hi` assignment). A udev rule creates **4 SR-IOV VFs** on the PF, distributed in
  `50-et100g`'s `[SR-IOV]` sections: VF 0 → `cellar` (VLAN hi), VF 1 → `river` (no VLAN — river
  tags all of its own VLANs, including both WAN VLANs, on this trunk), VF 2 → `sfh` (VLAN hi),
  VF 3 → `sfh`'s container MACVLAN parent (VLAN hi).
- `lan-core` is a bridge with the `core` assignment (`192.168.64.20`, no gateway); the 1G
  `lan-core-phy` and the `lan-lo-phy` VLAN ride on it. `lan-lo` is a second, L3-less bridge used
  for VM netboot and `lo` clients.
- The 1G `et1g0` (igb) is exported to `river` as a passthru-mode macvtap (`vm-et1g0`) — river sees
  it as `wan-old`.

## VMs

| VM | vCPUs | RAM | Passthrough | Notes |
|---|---|---|---|---|
| `cellar` | 8c × 2t | 16 GiB | VF 0 (`44:00.1`); NVMe `41:00.0`–`43:00.0` | pinned to NUMA node 1; split IRQ chip + vIOMMU |
| `river` | 3c × 2t | 4 GiB | VF 1 (`44:00.2`); macvtap `vm-et1g0` | only an ESP local disk (plus an installer ISO) — root is NVMe-oF from `cellar` |
| `sfh` | 8c × 2t | 32 GiB | VF 2 (`44:00.3`), VF 3 (`44:00.4`); two USB host ports | no boot disk — netboots; gets the `hdds/frigate` LV |

Boot ordering is enforced with systemd dependencies: `vm@river` waits for `cellar`'s SSH port (and
for the `vm-et1g0` device), and `vm@sfh` waits for `river` — storage first, then the router, then
everything that boots off both.

## Notable config files

- [`nixos/boxes/home/palace/default.nix`](../../../nixos/boxes/home/palace/default.nix) — host
  hardware, networkd (links/bridges/SR-IOV), LVM.
- [`nixos/boxes/home/palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix) —
  VM instances and boot ordering.
