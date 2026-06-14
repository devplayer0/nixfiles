# toot

A federated-social container. Despite the name (Mastodon = "toots"), it currently
hosts a **Bluesky PDS**; the Mastodon instance is disabled.

- **Source:** [`shill/containers/toot.nix`](../../../nixos/boxes/colony/vms/shill/containers/toot.nix)
- **Host:** NixOS container on `shill`

## Role

- **Bluesky PDS** (Personal Data Server) — the active service, published as
  `pds.nul.ie` (proxied by `middleman` to `:3000`).
- **Mastodon** — **currently disabled**. The config is still present and
  `toot.nul.ie` still maps to `:80`, but the instance is not running. (It was
  backed by the shared `colony-psql` and MinIO/S3 on `object`.)

## Networking

- `internal` assignment on the `ctrs` network (alt name `toot-ctr`).
