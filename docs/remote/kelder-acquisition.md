# kelder-acquisition

The media acquisition stack for the kelder site — Transmission (forced over VPN), the *arrs
and Jellyfin in one NixOS container.

- **Source:** [`nixos/boxes/kelder/containers/acquisition/`](../../nixos/boxes/kelder/containers/acquisition)
- **Host:** NixOS container on [`kelder`](kelder.md)

## Role

- **Transmission** (`transmission_4`) — BitTorrent client bound to the VPN
  (`bindsTo systemd-networkd-wait-online@vpn.service`); peer port 26180 (forwarded in the
  AirVPN config), 20 MiB/s down / 1 MiB/s up limits, ratio limit 2.0. Downloads land in
  `/mnt/media/downloads/torrents` (`/mnt/media` is bind-mounted from the host's
  `/mnt/storage/media`).
- **Jackett, Radarr, Sonarr** — indexer + media managers, in the shared `media` group with
  `UMask 0002`.
- **Jellyfin** — streaming with Intel hardware transcoding: `/dev/dri` is bind-mounted from
  the host, `intel-vaapi-driver`/`intel-ocl` are installed and the `jellyfin` user is in the
  `render` group.

## Network assignments

<!-- assignments: kelder-acquisition -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| acquisition-ctr | internal | `172.16.64.2/24 gw 172.16.64.1` | — | hentai.engineer |  |
<!-- assignments-end -->

## Networking

- `internal` assignment (name `acquisition-ctr`) on the host's `ctrs` bridge, MTU 1460 to
  match the site WAN.
- All non-site traffic goes over an AirVPN WireGuard tunnel (`vpn` netdev, MTU 1320, AirVPN
  IE endpoint) using fwmark 42 / route table 51820: policy rules keep traffic to and from the
  kelder prefixes on the main table and push everything else via the VPN.
- An nftables input chain drops new TCP connections from the VPN interface except the
  Transmission peer port; the web UI ports (9091 Transmission, 9117 Jackett, 7878 Radarr,
  8989 Sonarr, 8096 Jellyfin) are accepted from the site. When built as a dev VM, those ports
  are forwarded to the host.
- Sonarr still needs the EOL .NET 6 runtime, allowed via
  `nixpkgs.config.permittedInsecurePackages`.

## Notable config files

- [`nixos/boxes/kelder/containers/acquisition/default.nix`](../../nixos/boxes/kelder/containers/acquisition/default.nix) — services and users.
- [`nixos/boxes/kelder/containers/acquisition/networking.nix`](../../nixos/boxes/kelder/containers/acquisition/networking.nix) — AirVPN tunnel + firewall.
