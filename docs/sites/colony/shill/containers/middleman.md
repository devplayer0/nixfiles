# middleman

The front-end reverse proxy for the colony's public web services — the single ingress that
`estuary` DNATs HTTP/HTTPS (and Matrix federation on `:8448`) to. Terminates TLS with wildcard
certificates it issues itself, provides nginx-sso for gated vhosts, and runs a librespeed
backend.

- **Source:** [`shill/containers/middleman/`](../../../../../nixos/boxes/colony/vms/shill/containers/middleman)
  (`default.nix`, `vhosts.nix`)
- **Host:** NixOS container on [`shill`](../README.md) (`my.containers` ephemeral nspawn on the
  `ctrs` bridge; bind-mounts `/mnt/media` read-only for the static file vhosts)
- **nixpkgs:** `mine`

## Role

### nginx

The reverse proxy enables `vts`, `fancyindex`, Brotli, kTLS and a proxy cache. Its dynamic resolver
points at `estuary`, allowing upstreams named under `ams1.int.nul.ie` to resolve again at runtime.
All vhosts live in
[`vhosts.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/middleman/vhosts.nix). nginx
also waits for `colony-psql` through `systemdAwaitPostgres`, avoiding an early-boot DNS stall.

### ACME

`middleman` issues certificates for its own vhosts; it is not a shared CA for other boxes.

- `ams1.int.nul.ie` and its wildcard use a lego `exec` challenge that SSHes to
  `pdns-file-records@estuary-vm`. This is the default `useACMEHost` certificate internally.
- `nul.ie`, `*.nul.ie` and `*.s3.nul.ie` use Cloudflare DNS. A `postRun` hook copies renewed
  material to the `mail` VM and runs `mailcow-ssl-reload` there.
- Renewal reloads nginx; the `acme` group owns the secret files and includes the nginx user.

### nginx-sso

The `generic` SSO instance at `sso.nul.ie` uses Google OAuth by default and also offers a simple
username/password provider. Its cookie domain is `.nul.ie`; gated vhosts include the generated
`server-generic.conf` / `location-generic.conf` snippets from `/etc/nginx/includes/sso/`.

### librespeed

The frontend and backend are published as `speed.nul.ie` and `librespeed.ams1.int.nul.ie`, both
proxied to `localhost:8989`.

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `middleman`).

The firewall allows `http`, `https` and `8448` (Matrix federation). A small nftables SNAT rule
rewrites outbound IPv6 to the container's own address on `host0`.

## Published vhosts

Everything is under `*.nul.ie` with the public wildcard cert unless noted; defaults applied to
all vhosts are `onlySSL`, kTLS and HTTP/2. "SSO" = gated behind nginx-sso (`generic` instance).

| Host | Upstream | Notes |
| --- | --- | --- |
| `nul.ie` (`_`, default) | static | landing page (`index.html`, CV PDF, SSH pubkey); serves Matrix `.well-known`s and redirects `webfinger`/`nodeinfo`/`host-meta` → `toot.nul.ie`, `atproto-did` → `pds.nul.ie`; `forceSSL` (plain HTTP redirects to HTTPS) |
| `localhost` | — | loopback-only VTS status page at `/status` (scraped by netdata); plain HTTP |
| `sso.nul.ie` | `localhost:8082` | nginx-sso endpoint |
| `netdata-colony.nul.ie` | `<host>.ams1.int.nul.ie:19999` | netdata fan-out over `vm`, `fw`, `ctr`, `oci`, `http`, `jackflix-ctr`, `chatterbox-ctr`, `colony-psql-ctr`; **SSO** |
| `pass.nul.ie` | `vaultwarden-ctr:8080` | [vaultwarden](vaultwarden.md); `/notifications/hub` proxied with websockets |
| `matrix.nul.ie` | `chatterbox-ctr:8008` | [chatterbox](chatterbox.md) Synapse client + federation; also listens on `:8448` as federation `default_server`; `= /` redirects to Element; serves Matrix `.well-known`s |
| `element.nul.ie` | static `element-web` | Element configured for the `nul.ie` homeserver |
| `torrents.nul.ie` | `jackflix-ctr:9091` | Transmission ([jackflix](jackflix.md)); **SSO** |
| `jackett.nul.ie` | `jackflix-ctr:9117` | **SSO** |
| `radarr.nul.ie` | `jackflix-ctr:7878` | **SSO**; websockets |
| `sonarr.nul.ie` | `jackflix-ctr:8989` | **SSO**; websockets |
| `gib.nul.ie` | `jackflix-ctr:5055` | Jellyseerr requests |
| `jackflix.nul.ie` | `jackflix-ctr:8096` | Jellyfin; `/socket` websockets; `/` redirects to `/web/` |
| `toot.nul.ie` | `toot-ctr:80` | Mastodon — **upstream currently disabled**, see [toot](toot.md) |
| `pds.nul.ie` | `toot-ctr:3000` | Bluesky PDS ([toot](toot.md)); websockets |
| `stuff.nul.ie` | `jackflix-ctr:3923` | copyparty |
| `public.nul.ie` (+ alias `p.nul.ie`) | static `/mnt/media/public` | fancyindex file listing; `addSSL` so plain HTTP also works |
| `mc-map.nul.ie` | `simpcraft-oci:8100` | Minecraft map (OCI container on [`whale2`](../../whale2.md#game-servers)) |
| `mc-rail.nul.ie` | `simpcraft-oci:3876` | Minecraft railway map ([`whale2`](../../whale2.md#game-servers)) |
| `mc-map-kink.nul.ie` | `kinkcraft-oci:8100` | Minecraft map ([`whale2`](../../whale2.md#game-servers)) |
| `speed.nul.ie` | `localhost:8989` | librespeed |
| `librespeed.ams1.int.nul.ie` | `localhost:8989` | librespeed on the internal domain (internal wildcard cert) |
| `md.nul.ie` | `object-ctr:3000` | HedgeDoc; websockets |
| `pb.nul.ie` | `object-ctr:8088` | wastebin |
| `photos.nul.ie` | `jackflix-ctr:2342` | PhotoPrism; websockets |
| `pront.nul.ie` | `stream-hi.h.nul.ie:5000` | OctoPrint on the home network ([`stream`](../../../home/stream.md)); `/webcam/` → `:5050`; **SSO** |
| `hass.nul.ie` | `hass-ctr.h.nul.ie:8123` | [Home Assistant](../../../home/sfh/containers/hass.md) (home network); websockets |
| `hass-john.nul.ie` | `john-valorant-tun.ams1.int.nul.ie:8123` | remote Home Assistant over the point-to-point tunnel; websockets |
| `minio.nul.ie` | `object-ctr:9001` | MinIO console; `/ws` websockets |
| `s3.nul.ie` (+ `*.s3.nul.ie`) | `object-ctr:9000` | MinIO S3 API (virtual-host style via the `*.s3` wildcard cert); `/gitea/packages/` has a hack forcing the correct `Content-Type` for Docker image manifests |
| `nix-cache.nul.ie` | `object-ctr:5000` | Harmonia Nix binary cache; `.narinfo`/`nar/`/`serve/` paths get immutable `Cache-Control`/`Expires` headers |

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/middleman/default.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/middleman/default.nix) — container definition: nginx, ACME, nginx-sso, librespeed, secrets
- [`nixos/boxes/colony/vms/shill/containers/middleman/vhosts.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/middleman/vhosts.nix) — all virtual hosts, the SSO include helpers, and the `.well-known` tree
- [`nixos/boxes/colony/vms/shill/containers/middleman/default.html`](../../../../../nixos/boxes/colony/vms/shill/containers/middleman/default.html) — default vhost landing page
