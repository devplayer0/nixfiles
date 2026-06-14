# kelder-acquisition

The media stack for the `kelder` site — a slimmer cousin of colony's
[`jackflix`](../colony/jackflix.md).

- **Source:** [`kelder/containers/acquisition/`](../../../nixos/boxes/kelder/containers/acquisition)
  (`default.nix`, `networking.nix`)
- **Host:** NixOS container on `kelder`

## Role

- **Jellyfin** for streaming (with hardware transcoding — the `jellyfin` user is
  in the `render` group, `jellyfin-ffmpeg`).
- **Acquisition:** Transmission, Jackett, Radarr, Sonarr.
- Runs under the site's shared `kontent` user.

## Networking

- `internal` assignment (alt name `acquisition-ctr`) on the kelder container
  network; download client networking in `networking.nix`.
