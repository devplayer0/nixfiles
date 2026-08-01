# darts

An opaque third-party/customer VM. Declared in `colony`'s `my.vms.instances`
but **not a NixOS system**: this repo knows nothing about what runs inside it
and doesn't manage it.

- **Source (host-side only):** the `darts` instance in
  [`nixos/boxes/colony/vms/default.nix`](../../../nixos/boxes/colony/vms/default.nix)
  and the `90-vm-darts` network in
  [`nixos/boxes/colony/default.nix`](../../../nixos/boxes/colony/default.nix)
- **Host:** VM on `colony`
- **nixpkgs:** not applicable (unmanaged guest; host-side definition uses `colony`'s `mine-stable`)

## Role

- Customer/dedicated VM, left alone beyond hosting and connectivity.
- A thin-provisioned `root` LV on the NVMe pool, plus `darts-media` (RAID 5 across the four HDDs)
  and `darts-ext` (linear storage on the 18 TB HDD) in the `main` VG. See
  [`colony`'s storage layout](colony.md#storage).

## Network assignments

This guest is not a NixOS system, so its host-routed addresses are not rows in the generated
[network assignments](../../networking.md#box-assignments) table.

- Same customer-VM pattern as [`mail`](mail.md): dedicated unbridged TAP
  (`vm-darts`), point-to-point address
  (`custRouting.darts-vm`) on the host side, link-routed public /32
  `94.142.242.255`, and the IPv6 /64 `2a0e:97c0:4d2:2001::/64` with RAs.
- DNS: `darts-cust.ams1.int.nul.ie`. Like the other customer prefixes, its
  inbound traffic is accepted by `estuary` without per-port filtering and
  forwarded on by `colony`.

## Notable config files

- [`nixos/boxes/colony/vms/default.nix`](../../../nixos/boxes/colony/vms/default.nix) — VM definition.
- [`nixos/boxes/colony/default.nix`](../../../nixos/boxes/colony/default.nix) — host-side network and routing.
