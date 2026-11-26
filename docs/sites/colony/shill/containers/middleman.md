# middleman

The front-end reverse proxy for the colony's public web services — the single ingress that
`estuary` DNATs HTTP/HTTPS (and Matrix federation on `:8448`) to. Terminates TLS with wildcard
certificates it issues itself, runs the Pocket ID identity provider with oauth2-proxy in front of
gated vhosts, and runs a librespeed backend and a Paseo relay.

- **Source:** [`shill/containers/middleman/`](../../../../../nixos/boxes/colony/vms/shill/containers/middleman)
  (`default.nix`, `auth.nix`, `vhosts.nix`)
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
- `nul.ie`, `*.nul.ie`, `*.s3.nul.ie` and `*.slop.nul.ie` (for `slop-broker` previews) use
  Cloudflare DNS. A `postRun` hook copies renewed material to the `mail` VM and runs
  `mailcow-ssl-reload` there.
- Renewal reloads nginx; the `acme` group owns the secret files and includes the nginx user.

### Pocket ID

[Pocket ID](https://pocket-id.org) (`services.pocket-id`) is a passkey-only OpenID Connect
provider at `id.nul.ie`. Apps with OIDC support sign in with it directly (such as the
[`slop-broker` approvals web app](../../../../slop-broker.md#approvals-web-app)); the rest go
through [oauth2-proxy](#sso).

- Listens on `127.0.0.1:1411` behind nginx and keeps its SQLite database in `/var/lib/pocket-id`
  (persisted by `my.tmproot`). The `middleman/pocket-id-encryption-key` secret encrypts it.
- The first admin is created at `/setup`; nginx only allows that page and its API from
  internal networks (`lib.my.c.internalNets`). Further users are added from the admin UI.

**Declared groups and clients.** `my.pocket-id` (in
[`auth.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/middleman/auth.nix)) declares
user groups and OIDC clients; `pocket-id-sync` creates and updates them through the API on every
switch.

- It authenticates with the static API key `middleman/pocket-id-api-key`. nginx strips
  `X-API-Key` from outside requests, so API keys only work from inside the container.
- Clients and groups that aren't declared are left alone, as is group membership: add users to
  groups in the admin UI.
- A client's secret is an age file shared with the box that runs the app (or a key of an env
  file). Generate it with `slop secret generate`; after rotating one, restart `pocket-id-sync`.

### SSO

[oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) signs users in with Pocket ID (client
`sso`) for vhosts with no sign-in of their own.

- `ssoServer [ <groups> ]` in `vhosts.nix` gates a vhost with nginx `auth_request`, allowing
  members of any of the given Pocket ID groups. The gated vhosts currently allow `admins`.
- Each gated vhost serves oauth2-proxy's `/oauth2/` endpoints itself. Its session cookie is
  host-only, so other `.nul.ie` sites (including `*.slop.nul.ie` previews) never receive it.
  Pocket ID's own session turns signing in to another gated vhost into a redirect.
- The `sso` client's callback URLs are derived from the gated vhosts.
- Sessions last a week. Every hour, oauth2-proxy uses a refresh token to check back with Pocket
  ID without a passkey, and picks up the user's current groups. A disabled user is signed out at
  the next check; someone removed from a group loses access once their access token expires (an
  hour at most, Pocket ID's default).
- A location in a gated vhost with its own `add_header` would drop the refreshed session cookie
  that `ssoServer` passes on.
- Its client secret and cookie secret are in the env file `middleman/oauth2-proxy.env`.
- `id.nul.ie` resolves to the container itself, so oauth2-proxy reaches Pocket ID through the
  local nginx.

### librespeed

The frontend and backend are published as `speed.nul.ie` and `librespeed.ams1.int.nul.ie`, both
proxied to `localhost:8989`.

### Paseo relay

[`paseo-relay`](https://github.com/getpaseo/paseo-relay) (the `my.paseo-relay` module, package
`pkgs/paseo-relay.nix`) relays end-to-end encrypted traffic between Paseo daemons and the Paseo
app, in place of Paseo's hosted relay.

- Single node with no Erlang distribution, listening on `127.0.0.1:4000` and published as
  `paseo-relay.nul.ie`. It keeps no state, so a restart only drops connections.
- The relay can't read or forge messages, so the vhost is open to the world. Its Prometheus
  `/metrics` is not exposed; `/health` and `/ready` are.
- `slop.nul.ie` serves Paseo's web app as static files, taken from the same patched Paseo package
  (our Jujutsu fork) as the daemon, so deploy it together with
  [`slop-cannon`](../../../home/slop-cannon.md). Pairing links from our daemon point there, and the app connects through the relay,
  so nothing from `paseo.sh` is needed in the browser.

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `middleman`).

The firewall allows `http`, `https` and `8448` (Matrix federation). A small nftables SNAT rule
rewrites outbound IPv6 to the container's own address on `host0`.

## Published vhosts

Everything is under `*.nul.ie` with the public wildcard cert unless noted; defaults applied to
all vhosts are `onlySSL`, kTLS and HTTP/2. "SSO" = gated behind [oauth2-proxy](#sso).

| Host | Upstream | Notes |
| --- | --- | --- |
| `nul.ie` (`_`, default) | static | landing page (`index.html`, CV PDF, SSH pubkey); serves Matrix `.well-known`s and redirects `webfinger`/`nodeinfo`/`host-meta` → `toot.nul.ie`, `atproto-did` → `pds.nul.ie`; `forceSSL` (plain HTTP redirects to HTTPS) |
| `localhost` | — | loopback-only VTS status page at `/status` (scraped by netdata); plain HTTP |
| `id.nul.ie` | `localhost:1411` | Pocket ID; `/setup` only from internal networks; `X-API-Key` stripped |
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
| `paseo-relay.nul.ie` | `localhost:4000` | Paseo relay; websockets with long timeouts; `/metrics` blocked |
| `slop.nul.ie` | static Paseo web app | falls back to `index.html`; precompressed files served as-is |
| `approve.slop.nul.ie` | `palace.h.nul.ie:8095` | [`slop-broker`](../../../../slop-broker.md#approvals-web-app)'s approvals web app, which handles sign-in itself (Pocket ID) |
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

- [`nixos/boxes/colony/vms/shill/containers/middleman/default.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/middleman/default.nix) — container definition: nginx, ACME, librespeed, Paseo relay, secrets
- [`nixos/boxes/colony/vms/shill/containers/middleman/auth.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/middleman/auth.nix) — Pocket ID, its declared groups and clients, oauth2-proxy
- [`nixos/boxes/colony/vms/shill/containers/middleman/vhosts.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/middleman/vhosts.nix) — all virtual hosts, the `ssoServer` helper, and the `.well-known` tree
- [`nixos/boxes/colony/vms/shill/containers/middleman/default.html`](../../../../../nixos/boxes/colony/vms/shill/containers/middleman/default.html) — default vhost landing page
