# colony

The hosted dedicated server in Amsterdam (`ams1`). This is the public-facing
half of the boxes: almost everything reachable from the internet lives here.

- **Internal domain:** `ams1.int.nul.ie`
- **Public domain:** `nul.ie` (public services are published as `*.nul.ie`)
- **Source:** [`nixos/boxes/colony/`](../../../nixos/boxes/colony)

## Shape

`colony` is the physical VM host. It runs the VMs below; one of them (`shill`)
is itself a NixOS container host where most applications run.

```
colony (physical VM host)
├── estuary ── edge router / firewall / DNS / BGP
├── shill ──── NixOS container host ──┬── middleman    (reverse proxy, ACME, SSO)
│                                     ├── colony-psql  (shared PostgreSQL)
│                                     ├── vaultwarden  (password manager)
│                                     ├── chatterbox   (Matrix + bridges)
│                                     ├── toot         (Mastodon)
│                                     ├── jackflix     (media stack)
│                                     ├── object       (MinIO, Nix cache, …)
│                                     ├── waffletail   (Tailscale subnet router)
│                                     ├── qclk         (clock service)
│                                     └── gam          (game servers)
├── whale2 ─── podman/OCI host (game servers)
├── git ────── Gitea + Actions runner
├── mail ───── Debian VM running Mailcow (not NixOS — configured out of repo)
└── darts ──── third-party/customer VM (opaque to this repo)
```

## Machines

| Machine | Role | Docs |
| --- | --- | --- |
| `colony` | Physical VM host (AMD, LVM-thin, borgthin backups → rsync.net) | [colony.md](colony.md) |
| `estuary` | Edge router: WAN, firewall/NAT, DNS, BGP, IXP peering, WireGuard | [estuary.md](estuary.md) |
| `shill` | NixOS container host (see containers below) | [shill.md](shill.md) |
| `whale2` | podman/OCI host for game servers | [whale2.md](whale2.md) |
| `git` | Gitea + Gitea Actions runner | [git.md](git.md) |

### shill containers

| Container | Role | Docs |
| --- | --- | --- |
| `middleman` | Front-end nginx reverse proxy, ACME certs, nginx-sso, librespeed | [middleman.md](middleman.md) |
| `colony-psql` | Shared PostgreSQL (14) for colony services | [colony-psql.md](colony-psql.md) |
| `vaultwarden` | Vaultwarden (Bitwarden-compatible password manager) | [vaultwarden.md](vaultwarden.md) |
| `chatterbox` | Matrix homeserver + bridges (heisenbridge, mautrix-*) | [chatterbox.md](chatterbox.md) |
| `toot` | Bluesky PDS (Mastodon disabled) | [toot.md](toot.md) |
| `jackflix` | Media: Jellyfin, *arr stack, Transmission, PhotoPrism, copyparty | [jackflix.md](jackflix.md) |
| `object` | MinIO (S3), Harmonia (Nix cache), HedgeDoc, wastebin | [object.md](object.md) |
| `waffletail` | Tailscale subnet router (advertises colony prefixes into the tailnet) | [waffletail.md](waffletail.md) |
| `qclk` | `qclk` clock service (reachable over WireGuard) | [qclk.md](qclk.md) |
| `gam` | Game servers (Terraria, …) | [gam.md](gam.md) |

## Non-NixOS VMs

These run on `colony` but are **not** managed by this repo (no NixOS config). The
QEMU instances are still declared in `colony`'s `my.vms.instances`, and colony's
networking routes/firewalls traffic to them:

- **`mail`** — a Debian VM running [Mailcow](https://mailcow.email/) (`mail.nul.ie`).
  ACME certs are pushed to it from `middleman` (see [middleman.md](middleman.md)).
- **`darts`** — a third-party/customer VM; opaque to this repo, given a routed
  prefix and otherwise left alone.
