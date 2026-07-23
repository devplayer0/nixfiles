# toot

Federated-social container. Despite the name, the only service actually running is a **Bluesky
PDS** — the Mastodon instance ("toots") is **currently disabled**.

- **Source:** [`shill/containers/toot.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/toot.nix)
- **Host:** NixOS container on [`shill`](../../shill.md)

## Role

- **bluesky-pds** — the active service. `pds.nul.ie` on port `3000`, fronted by
  [middleman](middleman.md) (which also redirects `/.well-known/atproto-did` here). Invites
  required; blob store is the `pds` bucket on [object](object.md)'s MinIO (`s3.nul.ie`,
  `eu-central-1`), upload limit 50 MiB; federation settings point at the stock Bluesky
  infrastructure (`plc.directory`, `api.bsky.app`, `mod.bsky.app`, `bsky.network` crawlers).
  Secrets (including the S3 credentials) come from the `toot/pds.env` age secret. Email from
  `pds@nul.ie`.
- **mastodon** — **disabled** (`services.mastodon.enable = false`). The full config is still
  present: `LOCAL_DOMAIN = nul.ie` with `WEB_DOMAIN = toot.nul.ie`, Postgres on
  [colony-psql](colony-psql.md), local Redis, SMTP via `mail.nul.ie`, media in the `mastodon`
  MinIO bucket (`S3_ALIAS_HOST = mastodon.s3.nul.ie`), 4 streaming processes, and media
  auto-cleanup after 30 days. [middleman](middleman.md) still proxies `toot.nul.ie` →
  `toot-ctr:80` and redirects the `webfinger`/`nodeinfo`/`host-meta` well-knowns there, but with
  the service off those endpoints are dead. The config notes the removed `otpSecretFile` option
  would need addressing before Mastodon can come back.

## Network assignments

<!-- assignments: toot -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| toot-ctr | internal | `10.100.2.8/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::8/64` | ams1.int.nul.ie |  |
<!-- assignments-end -->

The firewall allows `http` (the Mastodon nginx vhost) and the PDS port `3000` besides netdata.

## Notes

- The local nginx still carries the Mastodon virtual host (`toot.nul.ie`) with proxy-header
  overrides for being behind `middleman` — part of the preserved-but-disabled Mastodon setup.
- `mastodon-init-dirs` appends the S3 secret key to Mastodon's `.secrets_env` (the module has no
  option for a secret-key file), and `mastodon-init-db` waits for `colony-psql` — moot while
  Mastodon is disabled.

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/toot.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/toot.nix) — container definition; active PDS config and the preserved (disabled) Mastodon config
