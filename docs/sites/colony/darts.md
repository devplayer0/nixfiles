# darts

An opaque third-party/customer VM. Declared in `colony`'s `my.vms.instances`
but **not a NixOS system**: this repo knows nothing about what runs inside it
and doesn't manage it.

- **Source (host-side only):** the `darts` instance in
  [`nixos/boxes/colony/vms/default.nix`](../../../nixos/boxes/colony/vms/default.nix)
  and the `90-vm-darts` network in
  [`nixos/boxes/colony/default.nix`](../../../nixos/boxes/colony/default.nix)
- **Host:** VM on `colony`

## Role

- Customer/dedicated VM, left alone beyond hosting and connectivity.
- 4 cores, 16 GiB RAM; a `root` LV plus `darts-media` and `darts-ext` LVs from
  the `media`/`ext` volume groups.

## Networking

- Same customer-VM pattern as [`mail`](mail.md): dedicated unbridged TAP
  (`vm-darts`, MAC `52:54:00:a8:29:cd`), point-to-point address
  (`custRouting.darts-vm`) on the host side, link-routed public /32
  `94.142.242.255`, and the IPv6 /64 `2a0e:97c0:4d2:2001::/64` with RAs.
- DNS: `darts-cust.ams1.int.nul.ie`. Like the other customer prefixes, its
  inbound traffic is accepted by `estuary` without per-port filtering and
  forwarded on by `colony`.
