# git

The Gitea VM — source hosting and CI for the boxes (`git.nul.ie`).

- **Source:** [`nixos/boxes/colony/vms/git/`](../../../nixos/boxes/colony/vms/git)
  (`default.nix`, `gitea.nix`, `gitea-actions.nix`)
- **Host:** VM on `colony`
- **nixpkgs:** `mine`

## Role

### Gitea

The Git forge at `git.nul.ie` (self-registration disabled), configured in
[`gitea.nix`](../../../nixos/boxes/colony/vms/git/gitea.nix).

- Backed by PostgreSQL on [`colony-psql`](shill/containers/colony-psql.md) (waited on via
  `lib.my.systemdAwaitPostgres`).
- LFS enabled; all object storage (incl. LFS and packages) is on MinIO at `s3.nul.ie` (bucket
  `gitea`, on [`object`](shill/containers/object.md)) — the secret is spliced into `app.ini` at
  startup.
- Mail goes out via `mail.nul.ie`, including the issue-reply incoming-mail poller.

### Gitea Actions runner

One Docker-mode instance (`main-docker`) on podman (privileged, `podman` network), configured in
[`gitea-actions.nix`](../../../nixos/boxes/colony/vms/git/gitea-actions.nix).

- Labels for `node:24-trixie` and the self-built `git.nul.ie/dev/actions-ubuntu:26.04` images.
- Runs as a fixed `gitea-runner` user (not `DynamicUser`) so it can read its token; jobs have a
  configured timeout.
- The action cache lives on a dedicated disk (`/var/cache/gitea-runner`).
- Executes the repo's own `.gitea/workflows/ci.yaml`.

### nginx

Terminates TLS for `git.nul.ie` (and a default vhost) and proxies to Gitea on `:3000`. ACME
(Let's Encrypt, production) issues `nul.ie` + `*.nul.ie` via the Cloudflare DNS-01 challenge.

### podman

Local container backend for the runner; `/var/lib/containers` is an XFS data disk, and the default
`10.88.0.0/16` podman subnet is allowed to forward.

## Network assignments

See the consolidated [network assignments](../../networking.md#box-assignments) table (this box: `git`).

## Storage

- `/var/lib/gitea` — the `git` LV (repositories, config).
- `/var/cache/gitea-runner` — the `gitea-actions-cache` LV.
- `/var/lib/containers` — the `oci` LV (XFS with project quotas). Despite the
  name this is local to the `git` VM and unrelated to `whale2`'s `oci`
  network.

## Notable config files

- [`nixos/boxes/colony/vms/git/default.nix`](../../../nixos/boxes/colony/vms/git/default.nix) — VM config, nginx + ACME, podman, firewall.
- [`nixos/boxes/colony/vms/git/gitea.nix`](../../../nixos/boxes/colony/vms/git/gitea.nix) — Gitea itself.
- [`nixos/boxes/colony/vms/git/gitea-actions.nix`](../../../nixos/boxes/colony/vms/git/gitea-actions.nix) — the Actions runner.
