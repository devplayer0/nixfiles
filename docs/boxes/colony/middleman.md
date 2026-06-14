# middleman

The front-end reverse proxy for all public colony web services — the single
ingress that `estuary` forwards HTTP/HTTPS to.

- **Source:** [`shill/containers/middleman/`](../../../nixos/boxes/colony/vms/shill/containers/middleman)
  (`default.nix`, `vhosts.nix`)
- **Host:** NixOS container on `shill`

## Role

- **nginx** reverse proxy ([`vhosts.nix`](../../../nixos/boxes/colony/vms/shill/containers/middleman/vhosts.nix)
  holds the per-service vhosts) with VTS stats, fancyindex, brotli, caching, and
  a dynamic resolver pointed at `estuary` so upstreams can be re-resolved at
  runtime. It is the single public ingress for almost every web service — colony,
  home, and beyond.
- **ACME** — issues the wildcard certificates that **its own** vhosts are served
  with (it is not a shared CA for the other boxes; `git`, `britway`, `kelder-spoder`, etc. each
  run their own ACME):
  - `nul.ie` / `*.nul.ie` (+ `*.s3.nul.ie`) via the Cloudflare DNS challenge,
  - the internal `ams1.int.nul.ie` / `*` via an `exec` challenge that calls
    `estuary`'s pdns over SSH.
  - As a one-off consumer, it then pushes the public cert to the `mail` (Mailcow)
    VM via `scp` + a remote `mailcow-ssl-reload`.
- **nginx-sso** — single-sign-on (`sso.nul.ie`) with Google OAuth and a simple
  username/password provider; protects the SSO-gated vhosts below.
- **librespeed** — speed-test frontend + backend (`librespeed.${domain}` /
  `speed.nul.ie`).

## Published vhosts

All under `*.nul.ie` with the wildcard cert unless noted. Upstreams are addressed
by their internal container/VM hostnames. "SSO" = gated behind nginx-sso.

| Host(s) | Upstream | Notes |
| --- | --- | --- |
| `nul.ie` (default `_`) | static | landing page (CV, SSH pubkey) + Matrix/atproto `.well-known` |
| `sso.nul.ie` | nginx-sso | SSO endpoint |
| `pass.nul.ie` | `vaultwarden` | password manager |
| `matrix.nul.ie` (+`:8448`) | `chatterbox` | Matrix client + federation |
| `element.nul.ie` | element-web | Matrix web client |
| `toot.nul.ie` | `toot` :80 | Mastodon (currently disabled — see [toot.md](toot.md)) |
| `pds.nul.ie` | `toot` :3000 | Bluesky PDS |
| `jackflix.nul.ie` | `jackflix` Jellyfin | streaming |
| `torrents` / `jackett` / `radarr` / `sonarr` `.nul.ie` | `jackflix` | *arr stack (**SSO**) |
| `gib.nul.ie` | `jackflix` Jellyseerr | requests |
| `photos.nul.ie` | `jackflix` PhotoPrism | |
| `stuff` / `public` / `p.nul.ie` | `jackflix` copyparty + `/mnt/media` | file sharing / index |
| `share.nul.ie` | `object` :9090 | |
| `minio` / `s3` / `*.s3.nul.ie` | `object` MinIO | S3 + console (Docker manifest MIME hack) |
| `nix-cache.nul.ie` | `object` Harmonia | Nix binary cache (immutable cache headers) |
| `md.nul.ie` / `pb.nul.ie` | `object` | HedgeDoc / wastebin |
| `mc-map` / `mc-rail` / `mc-map-kink` `.nul.ie` | `whale2` OCI | Minecraft maps |
| `netdata-colony.nul.ie` | many hosts :19999 | netdata fan-out (**SSO**) |
| `pront.nul.ie` | `stream-hi` (home) | print/webcam (**SSO**) |
| `hass.nul.ie` | `hass` (home) | Home Assistant |
| `hass-john.nul.ie` | `john-valorant-tun` | remote HASS over WireGuard tunnel |

## Networking

- `internal` assignment on the `ctrs` network; bind-mounts `/mnt/media` for
  serving static/media content.
- nginx waits for `colony-psql` before starting (DNS bootstrap hack).
