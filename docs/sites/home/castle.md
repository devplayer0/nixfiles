# castle

The home workstation / gaming desktop. Diskless-style: it netboots from `river` and keeps its
root storage on NVMe-oF volumes from `cellar`.

- **Source:** [`nixos/boxes/home/castle/`](../../../nixos/boxes/home/castle) (`default.nix`)
- **Host:** physical
- **nixpkgs:** `mine`

## Role

### Desktop

The AMD desktop runs the GUI stack (`my.gui.enable`, Sway/Wayland via home-manager), low-latency
PipeWire, Bluetooth and Thunderbolt. Local `libvirtd`/`virt-manager` and the IOMMU are enabled, but
the box has no VFIO or GPU-passthrough configuration.

### Netboot

With `my.netboot.client.enable`, the firmware iPXE-boots from the 2.5G NIC. Kea matches
`et2.5g`'s MAC and directs it to `boot.h.nul.ie` on [`river`](river.md).

### NVMe-oF root

`/nix`, `/persist` and `/home` are `/dev/nvmeof/*` LVs in `cellar`'s
`nqn.2016-06.io.spdk:castle` namespace (`my.nvme.boot`, RDMA). The initrd brings
up `et100g`/`lan-hi` with `roceBootModules`; the running network keeps
`KeepConfiguration=static` so networkd does not drop the storage address. The root filesystem is a
size-limited tmpfs (`my.tmproot`).

### Other configuration

Both firewalls are disabled on this trusted `hi` desktop. Other settings include `binfmt`
emulation for `aarch64-linux`/`armv7l-linux`, `recursive-nix`, Wireshark and `rdma-core`/`qperf`;
a `drm-amd-display` flicker patch remains commented out.

## Network assignments

See the consolidated [network assignments](../../networking.md#box-assignments) table (this box: `castle`).

## Hardware

| Component | Inventory |
|---|---|
| Platform | ASUS ProArt X670E-CREATOR WIFI |
| CPU | AMD Ryzen 9 7950X (16 cores / 32 threads) |
| Memory | 64 GiB |
| Graphics | Integrated AMD Radeon graphics |
| Network | Mellanox ConnectX-4 100G, Aquantia AQC113CS 10G, Intel I225-V 2.5G and MediaTek MT7922 Wi-Fi 6E controllers |
| System storage | No local root disk; the box netboots and uses the SPDK NVMe-oF namespace exported by `cellar` |

## Networking

- `et100g` (100G, MTU 9000) carries `lan-hi` (the `hi` assignment, also pinned by a kea
  reservation on its MAC) and `lan-lo`.
- `lan-lo` is a secondary network attachment: DHCPv4 with `UseGateway`/`UseDNS` off and RAs
  accepted with gateway/DNS use off — present for reaching `lo` devices, never a default route.
- `et2.5g` (netboot) and `et10g` are renamed but carry no network config.

## Notable config files

- [`nixos/boxes/home/castle/default.nix`](../../../nixos/boxes/home/castle/default.nix) — box
  config: netboot/NVMe-oF boot, 100G networking, GUI/audio, virtualisation.
