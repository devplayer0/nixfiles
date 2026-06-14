# tower

A laptop workstation — a Framework Laptop 13 (12th-gen Intel).

- **Source:** [`nixos/boxes/tower/default.nix`](../../../nixos/boxes/tower/default.nix)

## Role

- Framework Laptop 13 (12th-gen Intel) running the GUI environment
  (`my.gui.enable`) with home-manager on the `mine` channel.
- Joins the tailnet via the self-hosted Headscale on [`britway`](britway.md)
  (`tailscale up --login-server=https://hs.nul.ie --accept-routes`).
- Local virtualisation enabled (`kvm-intel`, IOMMU on).

> Unlike [`castle`](../home/castle.md), `tower` lives outside the `home/` box
> tree and boots from local disks rather than NVMe-oF.
