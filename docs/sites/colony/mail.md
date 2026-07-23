# mail

A Debian VM running [mailcow](https://mailcow.email/) (`mail.nul.ie`) — the
mail server for `nul.ie`. Declared in `colony`'s `my.vms.instances` but **not
a NixOS system**: everything inside the VM is configured out of band.

- **Source (host-side only):** the `mail` instance in
  [`nixos/boxes/colony/vms/default.nix`](../../../nixos/boxes/colony/vms/default.nix)
  and the `90-vm-mail` network in
  [`nixos/boxes/colony/default.nix`](../../../nixos/boxes/colony/default.nix)
- **Host:** VM on `colony`

## Role

- Runs the full mailcow stack (Postfix/Dovecot/SOGo/Rspamd) for `nul.ie`.
  Other colony services send through it as `mail.nul.ie` (e.g. Gitea, and the
  disabled Mastodon config).
- 3 cores, 6 GiB RAM; `root` and `data` LVM disks (the `vm-mail-data` LV is
  included in `colony`'s `borgthin` backups).

## Networking

- Attaches to a dedicated, unbridged TAP (`vm-mail`, MAC
  `52:54:00:a8:d1:03`). `colony` puts the point-to-point address
  (`custRouting.mail-vm`) on the host side, link-routes the public /32
  `94.142.241.227` down the tap, and serves the IPv6 /64
  `2a0e:97c0:4d2:2000::/64` with RAs.
- DNS: `mail-vm.ams1.int.nul.ie` (and `mail.nul.ie` publicly, incl. the PTR in
  estuary's reverse zone). `estuary` accepts traffic to the customer prefixes
  without per-port filtering; `colony` forwards it on ("trust for now").

## Notes

- ACME certificates are issued on `middleman` and pushed to the VM over SSH
  (`acme@mail.nul.ie mailcow-ssl-reload`, key `middleman/mailcow-ssh.key`);
  the VM's SSH host key is pinned at `.keys/mail-vm-host.pub`.
