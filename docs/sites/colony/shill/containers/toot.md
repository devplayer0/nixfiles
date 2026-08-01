# toot

Federated-social container. Despite the name, the only service actually running is a **Bluesky
PDS** — the Mastodon instance ("toots") is **currently disabled**.

- **Source:** [`shill/containers/toot.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/toot.nix)
- **Host:** NixOS container on [`shill`](../README.md)
- **nixpkgs:** `mine`

## Role

### Bluesky PDS

The active service listens on port 3000 as `pds.nul.ie`, fronted by [middleman](middleman.md),
which also redirects `/.well-known/atproto-did` here. It requires invites, applies an upload-size
limit, and stores blobs in [object](object.md)'s `pds` MinIO bucket. Federation uses the standard
Bluesky services and crawlers. `toot/pds.env` supplies secrets, including S3 credentials, and mail
comes from `pds@nul.ie`.

### Mastodon

Mastodon is disabled with `services.mastodon.enable = false`, but its configuration remains:

- `nul.ie` is the local domain and `toot.nul.ie` the web domain.
- PostgreSQL runs on [colony-psql](colony-psql.md), with local Redis and SMTP through `mail.nul.ie`.
- Media uses the `mastodon` MinIO bucket, a configured streaming-process pool, and periodic cleanup.
- [middleman](middleman.md) still proxies the dead vhost and `.well-known` endpoints.

The removed `otpSecretFile` option must be addressed before the service can return.

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `toot`).

The firewall allows `http` (the Mastodon nginx vhost) and the PDS port `3000` besides netdata.

## Notes

- The local nginx still carries the Mastodon virtual host (`toot.nul.ie`) with proxy-header
  overrides for being behind `middleman` — part of the preserved-but-disabled Mastodon setup.
- `mastodon-init-dirs` appends the S3 secret key to Mastodon's `.secrets_env` (the module has no
  option for a secret-key file), and `mastodon-init-db` waits for `colony-psql` — moot while
  Mastodon is disabled.

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/toot.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/toot.nix) — container definition; active PDS config and the preserved (disabled) Mastodon config
