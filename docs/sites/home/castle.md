# castle

The home workstation / gaming desktop. Diskless-style: it netboots from `river` and keeps its
root storage on NVMe-oF volumes from `cellar`.

- **Source:** [`nixos/boxes/home/castle/`](../../../nixos/boxes/home/castle) (`default.nix`)
- **Host:** physical

## Role

- AMD desktop running the GUI stack (`my.gui.enable`, Sway/Wayland via home-manager), PipeWire
  (low-latency `quantum 128`, EasyEffects, jacktrip), Bluetooth, Thunderbolt (`bolt`).
- **Netboot client** (`my.netboot.client.enable`): the firmware iPXE-boots off the 2.5G NIC —
  kea's client-class for `castle` matches `et2.5g`'s MAC (`c8:7f:54:6e:17:0f`) and points at
  `boot.h.nul.ie` on [`river`](river.md).
- **Root on NVMe-oF**: `/nix`, `/persist` and `/home` are `/dev/nvmeof/*` LVs on the
  `nqn.2016-06.io.spdk:castle` namespace from [`cellar`](cellar.md) (`my.nvme.boot`,
  `192.168.68.80`, RDMA). The initrd brings up `et100g`/`lan-hi` plus `roceBootModules` to reach
  it, and the running system keeps `KeepConfiguration=static` on `lan-hi` so networkd never drops
  the NVMe-oF address. The root itself is a 24 GiB tmpfs (`my.tmproot`).
- Local virtualisation: `libvirtd` + `virt-manager` are enabled and the IOMMU is on
  (`amd_iommu=on`), but no VFIO/GPU-passthrough is configured in the box config today.
- Both firewalls are off (`networking.firewall.enable` and `my.firewall.enable` — it's a trusted
  desktop on `hi`).
- Misc: `binfmt` emulation for `aarch64-linux`/`armv7l-linux`, `recursive-nix`, Wireshark,
  `rdma-core`/`qperf` for the RoCE link. A `drm-amd-display` flicker patch sits commented out in
  `kernelPatches`.

## Network assignments

<!-- assignments: castle -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| castle | hi | `192.168.68.40/22 gw 192.168.71.254` | `2a0e:97c0:4d0:1::3:1/64` | h.nul.ie |  |
<!-- assignments-end -->

## Networking

- `et100g` (100G, MTU 9000) carries `lan-hi` (the `hi` assignment, statically `.40` — also pinned
  by a kea reservation on its MAC) and `lan-lo`.
- `lan-lo` is a secondary leg: DHCPv4 with `UseGateway`/`UseDNS` off and RAs accepted with
  gateway/DNS use off — present for reaching `lo` devices, never a default route.
- `et2.5g` (netboot) and `et10g` are renamed but carry no network config.

## Notable config files

- [`nixos/boxes/home/castle/default.nix`](../../../nixos/boxes/home/castle/default.nix) — box
  config: netboot/NVMe-oF boot, 100G networking, GUI/audio, virtualisation.
