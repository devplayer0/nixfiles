# vaultwarden

[Vaultwarden](https://github.com/dani-garcia/vaultwarden), a Bitwarden-compatible password
manager, published as `pass.nul.ie` through [middleman](middleman.md).

- **Source:** [`shill/containers/vaultwarden.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/vaultwarden.nix)
- **Host:** NixOS container on [`shill`](../../shill.md)

## Role

- **vaultwarden** — HTTP on `[::]:8080`, WebSocket notifications on `3012` (both allowed through
  the firewall). Web vault enabled, signups disabled, Bitwarden push notifications enabled
  (`PUSH_ENABLED`). `DOMAIN` is `https://pass.nul.ie`.
- **SMTP** via `mail.nul.ie:587` (STARTTLS) as `pass@nul.ie`; credentials and other sensitive
  settings come from the `vaultwarden/config.env` age secret.
- **Backups** — a `borgbackup` job pushes `/var/lib/vaultwarden` to rsync.net
  (`zh2855@zh2855.rsync.net:borg/vaultwarden2`), repokey-encrypted (passphrase and SSH key from
  secrets), `zstd,10` compression, keeping 7 daily / 4 weekly / all monthly archives.

## Network assignments

<!-- assignments: vaultwarden -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| vaultwarden-ctr | internal | `10.100.2.3/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::3/64` | ams1.int.nul.ie |  |
<!-- assignments-end -->

## Persistence

`/var/lib/vaultwarden` is persisted through `my.tmproot.persistence` — like the other
`shill` containers the root is ephemeral and real state lives under `/persist` (bind-mounted
from the host's `/persist/containers/vaultwarden`).

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/vaultwarden.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/vaultwarden.nix) — container definition, service config and the borgbackup job
