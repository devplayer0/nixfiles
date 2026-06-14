# castle

A desktop workstation.

- **Source:** [`nixos/boxes/home/castle/default.nix`](../../../nixos/boxes/home/castle/default.nix)

## Role

- AMD desktop running the GUI environment (`my.gui.enable`, Sway / Wayland via
  home-manager).
- **Diskless-style boot:** its `/nix`, `/persist` and `/home` are NVMe-oF volumes
  served by [`cellar`](cellar.md) (`/dev/nvmeof/{nix,persist,home}`). The
  networking is careful not to drop the IP used for the NVMe-oF connection.
- Uses the `my.nvme` module for the NVMe-oF client setup.

## Networking

- Sits on the home network; depends on the high-speed link to `cellar` for its
  root storage.
