# object

Object storage and Nix binary cache, plus a couple of small self-hosted web
apps.

- **Source:** [`shill/containers/object.nix`](../../../nixos/boxes/colony/vms/shill/containers/object.nix)
- **Host:** NixOS container on `shill`

## Role

- **MinIO** — S3-compatible object storage (`s3.nul.ie` / `*.s3.nul.ie`). Backs
  several other services (Gitea LFS/artifacts, social-media uploads, …). Stored on the
  `/mnt/minio` volume (XFS, bind-mounted from `shill`).
- **Harmonia** — serves the Nix binary cache for all the boxes (`nix-cache.nul.ie`), backed
  by the `/mnt/nix-cache` volume.
- **atticd** — an alternative Nix cache (stores into MinIO/S3). **Currently
  disabled** — present in the config but not running.
- **HedgeDoc** — collaborative markdown notes.
- **wastebin** — pastebin.

## Networking

- `internal` assignment on the `ctrs` network (alt name `object-ctr`).
- `/mnt/minio` and `/mnt/nix-cache` bind-mounted read-write from `shill`.
