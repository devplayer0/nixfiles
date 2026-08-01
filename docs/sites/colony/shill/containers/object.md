# object

Object storage and the Nix binary cache, plus a few small self-hosted web apps (Sharry,
HedgeDoc, wastebin).

- **Source:** [`shill/containers/object.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/object.nix)
- **Host:** NixOS container on [`shill`](../README.md) (bind-mounts `/mnt/minio` and
  `/mnt/nix-cache` read-write)
- **nixpkgs:** `mine`

## Role

| Service | Port | Purpose |
| --- | --- | --- |
| MinIO | `9000` (S3) / `9001` (console) | S3-compatible object storage, `s3.nul.ie` + `*.s3.nul.ie` (virtual-host style via `MINIO_DOMAIN`), console at `minio.nul.ie`; region `eu-central-1`; data on the `/mnt/minio` XFS volume |
| Harmonia | `5000` | Nix binary cache at `nix-cache.nul.ie` — `harmonia-dev` cache serves `shill`'s `/nix/store` out of a dedicated store view rooted at `/var/lib/harmonia` (bind-mounted from `/mnt/nix-cache`), signed with the `nix-cache.key` secret; a `harmonia` user with authorized keys exists for cache pushes |
| Sharry | `9090` | file sharing at `share.nul.ie`; Postgres on [colony-psql](colony-psql.md), files stored in the `share` MinIO bucket; fixed `dev` account + invite signup; mail via `mail.nul.ie`; configured share-size limit |
| HedgeDoc | `3000` | collaborative markdown notes at `md.nul.ie`; Postgres on [colony-psql](colony-psql.md); anonymous edits but no anonymous notes, email login, no open email registration |
| wastebin | `8088` | pastebin at `pb.nul.ie` |
| atticd | `8069` | **currently disabled** (`services.atticd.enable = false`) — an alternative Nix cache that would store locally and sit behind `nix-cache.nul.ie`; config (including the `object/atticd.env` secret) is kept around |

Everything public is fronted by [middleman](middleman.md) (see its vhost table). The
`minio-client` is installed and the user's `~/.mc/config.json` points at an age-secret config.
`minio-2025-10-15T17-29-55Z` is allowlisted via `permittedInsecurePackages` (flagged as a TODO).

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `object`).

## Backing services

- [colony-psql](colony-psql.md) — Sharry and HedgeDoc databases (atticd too, when enabled).
- MinIO buckets back other boxes' services: Gitea LFS/packages (with the `middleman` MIME hack
  for Docker manifests), Mastodon's `mastodon` bucket and the Bluesky PDS `pds` bucket on
  [toot](toot.md), and Sharry's `share` bucket.

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/object.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/object.nix) — container definition and all services
