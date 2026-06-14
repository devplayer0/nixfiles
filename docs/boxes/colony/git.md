# git

The Gitea VM — source hosting and CI for the boxes (`git.nul.ie`).

- **Source:** [`nixos/boxes/colony/vms/git/`](../../../nixos/boxes/colony/vms/git)
  (`default.nix`, `gitea.nix`, `gitea-actions.nix`)
- **nixpkgs:** `mine`
- **Host:** VM on `colony`

## Role

- **Gitea** ([`gitea.nix`](../../../nixos/boxes/colony/vms/git/gitea.nix)) — the Git
  forge (`git.nul.ie`). PostgreSQL-backed (the shared `colony-psql`), LFS
  enabled, with object storage backed by MinIO on `object` (a MinIO secret is
  spliced into `app.ini` at startup).
- **Gitea Actions runner**
  ([`gitea-actions.nix`](../../../nixos/boxes/colony/vms/git/gitea-actions.nix)) — a
  Docker-mode runner (`main-docker`) using podman. Labels provide Debian/node-24
  (Trixie) and Ubuntu 26.04 images; runner config comes from the upstream
  module's `settings` option. The Actions cache lives on a dedicated disk
  (`/var/cache/gitea-runner`). Runs as a fixed `gitea-runner` user (not
  `DynamicUser`) so it can read its token.
- **nginx** — terminates TLS for `git.nul.ie` and proxies to Gitea on `:3000`.
  ACME certs for `nul.ie` / `*.nul.ie` via the Cloudflare DNS challenge.
- **podman** — also hosts the OCI registry/build images; `/var/lib/containers`
  is an XFS data disk.

## Networking

- `vms` interface with `routing` / `internal` assignments.
- HTTP/HTTPS forwarded in from `estuary`; podman default subnet `10.88.0.0/16` is
  allowed to forward.

## CI

This runner is what executes the repo's own `.gitea/workflows/ci.yaml`, building
each `.#ci.x86_64-linux` attribute and pushing to the Harmonia binary cache. See
[`AGENTS.md`](../../../AGENTS.md#commands).
