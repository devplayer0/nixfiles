# jackflix

The media stack — acquisition, library and streaming.

- **Source:** [`shill/containers/jackflix/`](../../../nixos/boxes/colony/vms/shill/containers/jackflix)
  (`default.nix`, `networking.nix`)
- **Host:** NixOS container on `shill`

## Role

- **Streaming:** Jellyfin.
- **Acquisition (*arr stack):** Transmission, Jackett, FlareSolverr, Radarr,
  Sonarr, and Jellyseerr (`seerr`) for requests.
- **Photos:** PhotoPrism (`photos.nul.ie`).
- **File sharing:** copyparty (`:3923`) serving public + private media volumes.
- Media lives on the shared `/mnt/media` volume (bind-mounted read-write from
  `shill`). Downloaders bind to a VPN interface
  ([`networking.nix`](../../../nixos/boxes/colony/vms/shill/containers/jackflix/networking.nix)),
  so torrent traffic only flows while `systemd-networkd-wait-online@vpn` is up.
- A shared `media` group (gid 2000) gives the apps coordinated access.

## Networking

- `internal` assignment on the `ctrs` network (alt name `jackflix-ctr`), plus its
  own VPN interface for the download clients.
