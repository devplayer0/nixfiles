# tower

Portable workstation — a Framework Laptop 13 (Intel), running the full GUI environment.

- **Source:** [`nixos/boxes/tower/default.nix`](../../nixos/boxes/tower/default.nix)
- **Host:** physical (laptop)

## Role

- Personal portable workstation: `my.gui.enable`, with Sway managed by home-manager.
- Joins the tailnet through the headscale on [`britway`](../remote/britway.md) (fish abbr
  `tsup` = `doas tailscale up --login-server=https://hs.nul.ie --accept-routes`).

## Hardware / platform

- Intel platform: microcode updates, `kvm-intel`, `intel_iommu=on`, `intel-media-driver` for
  graphics; latest kernel (`lib.my.c.kernel.latest`).
- Thunderbolt security (`bolt`), Bluetooth (`blueman` + tray applet), fingerprint reader
  (`fprintd`; `doas` persists auth for `wheel`).
- `tlp` power management, including battery charge thresholds (start 90% / stop 97%).

## Storage

- Two LUKS-encrypted partitions, `persist` and `home` (both `allowDiscards`); `/nix` is a
  separate ext4 filesystem, `/boot` is vfat.
- Persistent `/home` (`my.user.tmphome = false`) with an 8G tmpfs root
  (`my.tmproot.size = "8G"`).

## Networking / services

- NetworkManager (`wpa_supplicant` backend) with `systemd-resolved`; networkd `wait-online`
  is disabled. The Wi-Fi interface is renamed to `wifi` by MAC.
- Steam and Wireshark enabled; `fstrim`, LVM thin provisioning.
- `nix.gc.automatic = false` — GC is run manually on the laptop.

## Notable config files

- [`nixos/boxes/tower/default.nix`](../../nixos/boxes/tower/default.nix) — the whole box (single file).
