# kelder-spoder

The web container for the kelder site: Nextcloud plus an nginx (OpenResty) reverse proxy for
the site's services.

- **Source:** [`nixos/boxes/kelder/containers/spoder/`](../../../../nixos/boxes/kelder/containers/spoder)
- **Host:** NixOS container on [`kelder`](../README.md)
- **nixpkgs:** `mine`

## Role

- **Nextcloud** (`nextcloud32`) at `cloud.hentai.engineer` (trusted alias
  `cloud-local.hentai.engineer`), SQLite backend, data in `/mnt/storage/nextcloud`
  (`/mnt/storage` is bind-mounted from the host).
- **nginx reverse proxy** (`openresty`) terminating TLS for the site's public vhosts, with a
  wildcard ACME cert for `hentai.engineer` via Cloudflare DNS. The kelder host forwards
  `http`/`https` to this container; uploads are unlimited (`clientMaxBodySize = 0`) for
  Nextcloud's sake.

## Network assignments

See the consolidated [network assignments](../../../networking.md#box-assignments) table (this box: `kelder-spoder`).

## Proxy vhosts

All under `hentai.engineer`, each with a `*-local` alias:

| vhost | Target | Auth |
| --- | --- | --- |
| `monitor` | `netdata` on the kelder host (:19999) | `htpasswd` |
| `kontent` | Jellyfin on `kelder-acquisition` (:8096, incl. websocket) | — |
| `torrents` | Transmission on `kelder-acquisition` (:9091) | `htpasswd` |
| `jackett` | Jackett on `kelder-acquisition` (:9117) | `htpasswd` |
| `radarr` | Radarr on `kelder-acquisition` (:7878) | `htpasswd` |
| `sonarr` | Sonarr on `kelder-acquisition` (:8989) | `htpasswd` |
| `cloud` | Nextcloud (local) | — |

An `init_worker_by_lua` timer polls `v4.ident.me` periodically to track the site's public IP; it
feeds `localRedirect` rewrites (bounce public-IP clients to the `*-local` name) that
are currently **disabled** (commented out — Virgin Media filters DNS answers containing local
IPs, so the split doesn't work as intended).

## Networking

- `internal` assignment (name `spoder-ctr`) on the host's `ctrs` bridge, MTU 1420.

## Notable config files

- [`nixos/boxes/kelder/containers/spoder/default.nix`](../../../../nixos/boxes/kelder/containers/spoder/default.nix) — Nextcloud + ACME.
- [`nixos/boxes/kelder/containers/spoder/nginx.nix`](../../../../nixos/boxes/kelder/containers/spoder/nginx.nix) — reverse proxy vhosts.
