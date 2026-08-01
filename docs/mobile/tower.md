# tower

Portable workstation — a Framework Laptop 13 (Intel), running the full GUI environment.

- **Source:** [`nixos/boxes/tower/default.nix`](../../nixos/boxes/tower/default.nix)
- **Host:** physical (laptop)
- **nixpkgs:** `mine`

## Hardware / platform

| Component | Inventory |
|---|---|
| Platform | Framework Laptop 13 (12th Gen Intel Core) |
| CPU | Intel Core i5-1240P (12 cores / 16 threads) |
| Memory | 32 GiB |
| Storage | 2 TB WD Black SN850 NVMe SSD |
| Graphics | Integrated Intel Iris Xe |
| Connectivity | Intel AX210 Wi-Fi 6E, Bluetooth and Thunderbolt 4 |

The configuration enables Intel microcode updates, `kvm-intel`, `intel_iommu=on`,
`intel-media-driver` and the latest kernel (`lib.my.c.kernel.latest`). Thunderbolt security
(`bolt`), the fingerprint reader (`fprintd`) and `tlp` power management are also enabled.

## Role

- Personal portable workstation: `my.gui.enable`, with Sway managed by home-manager.
- Joins the tailnet through the headscale on [`britway`](../remote/britway.md) (fish abbr
  `tsup` = `doas tailscale up --login-server=https://hs.nul.ie --accept-routes`).

## Network assignments

`tower` has no static assignment; it uses DHCP through NetworkManager and reaches the other boxes
over Tailscale.

## Storage

- Two LUKS-encrypted partitions, `persist` and `home` (both `allowDiscards`); `/nix` is a
  separate ext4 filesystem, `/boot` is vfat.
- Persistent `/home` (`my.user.tmphome = false`) with a size-limited tmpfs root (`my.tmproot.size`).

## Networking / services

- NetworkManager (`wpa_supplicant` backend) with `systemd-resolved`; networkd `wait-online`
  is disabled. The Wi-Fi interface is renamed to `wifi` by MAC.
- Steam and Wireshark enabled; `fstrim`, LVM thin provisioning.
- `nix.gc.automatic = false` — GC is run manually on the laptop.

## Notable config files

- [`nixos/boxes/tower/default.nix`](../../nixos/boxes/tower/default.nix) — the whole box (single file).
