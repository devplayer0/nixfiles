# kelder-acquisition

The media acquisition stack for the kelder site — Transmission (forced over VPN), the *arrs
and Jellyfin in one NixOS container.

- **Source:** [`nixos/boxes/kelder/containers/acquisition/`](../../../../nixos/boxes/kelder/containers/acquisition)
- **Host:** NixOS container on [`kelder`](../README.md)
- **nixpkgs:** `mine`

## Role

### Transmission

`transmission_4` is bound to the VPN wait-online unit and uses AirVPN's forwarded peer port. Upload,
download and seed-ratio limits are configured in the service source. Downloads use
`/mnt/media/downloads/torrents`, backed by the host's `/mnt/storage/media`.

### Media services

Jackett, Radarr and Sonarr share the `media` group with a group-writable umask. Jellyfin uses the
host's bind-mounted `/dev/dri` with `intel-vaapi-driver` / `intel-ocl`; its user belongs to
`render`.

## Network assignments

See the consolidated [network assignments](../../../networking.md#box-assignments) table (this box: `kelder-acquisition`).

## Networking

- `internal` assignment (name `acquisition-ctr`) on the host's `ctrs` bridge, MTU 1460 to
  match the site WAN.
- All non-site traffic goes over an AirVPN WireGuard tunnel (`vpn` netdev, AirVPN IE endpoint).
  Policy rules keep traffic to and from the kelder prefixes on the main table and push everything
  else through the VPN's dedicated table.
- An nftables input chain drops new TCP connections from the VPN interface except the
  Transmission peer port; the web UI ports (9091 Transmission, 9117 Jackett, 7878 Radarr,
  8989 Sonarr, 8096 Jellyfin) are accepted from the site. When built as a dev VM, those ports
  are forwarded to the host.
- Sonarr still needs the EOL .NET 6 runtime, allowed via
  `nixpkgs.config.permittedInsecurePackages`.

## Notable config files

- [`nixos/boxes/kelder/containers/acquisition/default.nix`](../../../../nixos/boxes/kelder/containers/acquisition/default.nix) — services and users.
- [`nixos/boxes/kelder/containers/acquisition/networking.nix`](../../../../nixos/boxes/kelder/containers/acquisition/networking.nix) — AirVPN tunnel + firewall.
