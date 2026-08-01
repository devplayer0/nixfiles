# jackflix

The media stack — acquisition, library, streaming and photos. Torrent traffic is routed through
an AirVPN WireGuard tunnel so downloads only flow while the VPN is up.

- **Source:** [`shill/containers/jackflix/`](../../../../../nixos/boxes/colony/vms/shill/containers/jackflix)
  (`default.nix`, `networking.nix`)
- **Host:** NixOS container on [`shill`](../README.md) (bind-mounts `/mnt/media` read-write)
- **nixpkgs:** `mine`

## Role

| Service | Port | Purpose |
| --- | --- | --- |
| Jellyfin | `8096` | streaming, published as `jackflix.nul.ie` |
| Transmission | `9091` | BitTorrent client (`transmission_4`), published as `torrents.nul.ie` (SSO) |
| Jackett | `9117` | indexer aggregator, `jackett.nul.ie` (SSO) |
| FlareSolverr | — | Cloudflare challenge solver for Jackett |
| Radarr | `7878` | movies, `radarr.nul.ie` (SSO) |
| Sonarr | `8989` | TV, `sonarr.nul.ie` (SSO) |
| Jellyseerr (`seerr`) | `5055` | request portal, `gib.nul.ie` (`openFirewall` on) |
| PhotoPrism | `2342` | photos, `photos.nul.ie`; password auth, sqlite DB, originals/import under `/mnt/media/photoprism` |
| copyparty | `3923` | file sharing, `stuff.nul.ie`; serves `/mnt/media/public` (read-only to everyone) and `/priv` → `/mnt/media/stuff` (admin for `dev`), share creation, indexing (`e2dsa`/`e2t`), file-magic checks |

All published through [middleman](middleman.md) as shown. A shared `media` group plus a group-writable
umask on Radarr/Sonarr gives the apps coordinated access to the media volume.

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `jackflix`).

## VPN download path

[`networking.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/jackflix/networking.nix)
defines a `vpn` WireGuard netdev to **AirVPN NL** using a key and PSK from age secrets:

- Policy routing keeps colony traffic on the main table while everything else falls through to the
  VPN's dedicated table, so the services stay reachable on the `ctrs` network while outbound
  torrent traffic exits via AirVPN. `DNSDefaultRoute` is disabled on `host0`; the VPN provides DNS.
- `transmission` and `jackett` `bindsTo` `systemd-networkd-wait-online@vpn.service` — they only
  run while the tunnel is up.
- AirVPN forwards a peer port to Transmission (`peer-port`); the firewall accepts it and drops
  other new inbound TCP from `vpn`, while non-VPN input is limited to the service ports
  (netdata, Transmission, Jackett, Radarr, Sonarr, Jellyfin, PhotoPrism) plus copyparty's `3923`
  from the base config and Jellyseerr's `5055`.

## Storage

Media lives on the shared `/mnt/media` volume (bind-mounted read-write from `shill`); Transmission
downloads into `/mnt/media/downloads/torrents` with a `.incomplete` directory and configured
bandwidth and seed-ratio limits.

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/jackflix/default.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/jackflix/default.nix) — container definition and the media services
- [`nixos/boxes/colony/vms/shill/containers/jackflix/networking.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/jackflix/networking.nix) — AirVPN WireGuard netdev, policy routing and VPN firewall rules
