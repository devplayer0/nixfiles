# vaultwarden

[Vaultwarden](https://github.com/dani-garcia/vaultwarden), a Bitwarden-compatible password
manager, published as `pass.nul.ie` through [middleman](middleman.md).

- **Source:** [`shill/containers/vaultwarden.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/vaultwarden.nix)
- **Host:** NixOS container on [`shill`](../README.md)
- **nixpkgs:** `mine`

## Role

- **vaultwarden** — HTTP on `[::]:8080`, WebSocket notifications on `3012` (both allowed through
  the firewall). Web vault enabled, signups disabled, Bitwarden push notifications enabled
  (`PUSH_ENABLED`). `DOMAIN` is `https://pass.nul.ie`.
- **SMTP** via `mail.nul.ie:587` (STARTTLS) as `pass@nul.ie`; credentials and other sensitive
  settings come from the `vaultwarden/config.env` age secret.
- **Backups** — a `borgbackup` job pushes `/var/lib/vaultwarden` to rsync.net
  using a repokey-encrypted repository; its passphrase and SSH key come from secrets, and the job
  keeps daily, weekly and monthly archives according to its configured retention policy.

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `vaultwarden`).

## Persistence

`/var/lib/vaultwarden` is persisted through `my.tmproot.persistence` — like the other
`shill` containers the root is ephemeral and real state lives under `/persist` (bind-mounted
from the host's `/persist/containers/vaultwarden`).

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/vaultwarden.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/vaultwarden.nix) — container definition, service config and the borgbackup job
