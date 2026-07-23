# colony

The hosted dedicated server in Amsterdam (`ams1`) and the public-facing half of
the boxes: almost everything reachable from the internet lives here.

- **Internal domain:** `ams1.int.nul.ie` (`lib.my.c.colony.domain`)
- **Public domain:** `nul.ie` — public services are published as `*.nul.ie`
- **Source:** [`nixos/boxes/colony/`](../../../nixos/boxes/colony)

## Shape

`colony` is the physical VM host. It runs the VMs below; `shill` is itself a
NixOS container host where most applications run.

```
colony (physical VM host, ams1)
├── estuary ── edge router: WAN, firewall/NAT, DNS, BGP (AS211024), WireGuard
├── shill ──── NixOS container host ──┬── middleman    (reverse proxy, ACME, nginx-sso, librespeed)
│                                     ├── vaultwarden  (password manager)
│                                     ├── colony-psql  (shared PostgreSQL)
│                                     ├── chatterbox   (Matrix Synapse + bridges)
│                                     ├── jackflix     (media stack)
│                                     ├── object       (MinIO, Harmonia Nix cache, Sharry, HedgeDoc, wastebin)
│                                     ├── toot         (Bluesky PDS; Mastodon disabled)
│                                     ├── waffletail   (Tailscale subnet router / exit node)
│                                     ├── qclk         (WireGuard management appliance)
│                                     ├── gam          (Terraria server)
│                                     └── jam          (raw nspawn customer container)
├── whale2 ─── podman/OCI host for game servers
├── git ────── Gitea + Gitea Actions runner
├── mail ───── Debian VM running mailcow (not NixOS)
└── darts ──── third-party/customer VM (opaque, not NixOS)
```

## Networks

All internal space is carved out of `10.100.0.0/16` and `2a0e:97c0:4d2:10::/60`
(`lib.my.c.colony.prefixes`):

| Network | IPv4 CIDR | IPv6 CIDR | Purpose |
|---|---|---|---|
| `base` | `10.100.0.0/24` | `2a0e:97c0:4d2:10::/64` | Base LAN shared by `colony` and `estuary` |
| `vms` | `10.100.1.0/24` | `2a0e:97c0:4d2:11::/64` | VM network |
| `ctrs` | `10.100.2.0/24` | `2a0e:97c0:4d2:12::/64` | `shill` container network |
| `oci` | `10.100.3.0/24` | `2a0e:97c0:4d2:13::/64` | `whale2` podman network |

Public addressing — the WAN /24 (`94.142.240.44`), the `vip*` ranges shared by
the VMs, and the customer /32s for `mail` / `darts` — terminates on `estuary`;
see [estuary.md](estuary.md).

## Machines

| Machine | Role | Page |
|---|---|---|
| `colony` | Physical VM host (AMD, KVM, LVM-thin, `borgthin` backups → rsync.net) | [colony.md](colony.md) |
| `estuary` | Edge router: WAN, firewall/NAT, DNS, BGP (AS211024), WireGuard | [estuary.md](estuary.md) |
| `shill` | NixOS container host (most applications) | [shill.md](shill.md) |
| `whale2` | podman/OCI game-server host | [whale2.md](whale2.md) |
| `git` | Gitea + Gitea Actions runner | [git.md](git.md) |
| `mail` | Debian VM running mailcow (not NixOS) | [mail.md](mail.md) |
| `darts` | Third-party/customer VM (not NixOS) | [darts.md](darts.md) |

### `shill` containers

Each has its own page under `shill/containers/`:

| Container | Role | Page |
|---|---|---|
| `middleman` | Front-end nginx reverse proxy, ACME, nginx-sso, librespeed | [middleman](shill/containers/middleman.md) |
| `vaultwarden` | Vaultwarden password manager | [vaultwarden](shill/containers/vaultwarden.md) |
| `colony-psql` | Shared PostgreSQL for colony services | [colony-psql](shill/containers/colony-psql.md) |
| `chatterbox` | Matrix homeserver + bridges | [chatterbox](shill/containers/chatterbox.md) |
| `jackflix` | Media stack (Jellyfin, *arr, Transmission, PhotoPrism, copyparty) | [jackflix](shill/containers/jackflix.md) |
| `object` | MinIO (S3), Harmonia Nix cache, Sharry, HedgeDoc, wastebin | [object](shill/containers/object.md) |
| `toot` | Bluesky PDS (Mastodon disabled) | [toot](shill/containers/toot.md) |
| `waffletail` | Tailscale subnet router / exit node | [waffletail](shill/containers/waffletail.md) |
| `qclk` | WireGuard management appliance | [qclk](shill/containers/qclk.md) |
| `gam` | Terraria server | [gam](shill/containers/gam.md) |

## Non-NixOS VMs

Two VMs are declared in `colony`'s `my.vms.instances` — so `colony` runs them
and routes/firewalls their traffic — but they are **not** managed as NixOS
systems by this repo:

- **`mail`** — a Debian VM running [mailcow](https://mailcow.email/)
  (`mail.nul.ie`). ACME certificates are pushed to it from `middleman`.
  See [mail.md](mail.md).
- **`darts`** — an opaque third-party/customer VM, given a routed public /32
  and IPv6 /64 and otherwise left alone. See [darts.md](darts.md).
