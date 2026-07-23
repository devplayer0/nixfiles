# kelder

Secondary home server at a remote site, domain `hentai.engineer`. Linked back to colony over
WireGuard and acting as a NixOS container host (like `shill`/`sfh`).

- **Source:** [`nixos/boxes/kelder/`](../../nixos/boxes/kelder)
- **Host:** physical (Intel; LTS kernel, `kvm-intel`, IOMMU on)

## Role

- **Container host** — runs two NixOS containers on the `ctrs` bridge
  (`my.containers.instances`): `kelder-acquisition` and `kelder-spoder` (below).
- **Public services via colony** — a WireGuard tunnel (`estuary` netdev) connects to colony's
  `estuary` box, which DNATs public traffic to kelder's `/32`; policy routing (table 51820 +
  connmark) sends replies back through the tunnel while ordinary traffic uses the LAN.
  kelder's own NAT forwards `http`/`https` on to `kelder-spoder`.
- **Nextcloud host** — served from the `kelder-spoder` container.
- **Samba** — the `storage` share backed by `/mnt/storage`, with `nmbd` and `samba-wsdd` for
  Windows discovery.
- **DDNS** — a `ddns-update` timer (every 10 min) runs `dns_update.py` to sync the
  `hentai.engineer` and `kelder-local.hentai.engineer` Cloudflare records with the address on
  `et1g0`.

## Network assignments

<!-- assignments: kelder -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| kelder-ctrs | ctrs | `172.16.64.1/24` | — | hentai.engineer |  |
| kelder | estuary | `94.142.242.254/32` | — | — |  |
<!-- assignments-end -->

## Containers

| Container | Role | Docs |
| --- | --- | --- |
| `kelder-acquisition` | Media stack (Transmission over AirVPN, Jackett/Radarr/Sonarr, Jellyfin) | [kelder-acquisition.md](kelder-acquisition.md) |
| `kelder-spoder` | Nextcloud + nginx reverse proxy | [kelder-spoder.md](kelder-spoder.md) |

The containers are not deploy targets (`my.deploy.enable = false`); they're managed through
the host.

## Networking

- LAN on `et1g0` (renamed by MAC) with DHCP and MTU 1460 (`lib.my.c.kelder.ipv4MTU`); the
  kelder v4 prefixes are masqueraded out of it.
- The `estuary` WireGuard peer (`AllowedIPs = 0.0.0.0/0`, keepalive 25s) is combined with
  rules that keep LAN traffic on the main table and only route tunnel-marked/owned traffic
  via table 51820.

## Services

- `netdata` (proxied as `monitor.hentai.engineer` by `kelder-spoder`), `smartd`, `fstrim`,
  LVM thin provisioning.
- `minecraft-server` is present but **disabled** (`enable = false`); the firewall still opens
  25565 tcp/udp.
- Primary user `kontent` (in the `storage`/`media` groups).
- Sets `system.nixos.distroName = "KelderOS"`, a custom Plymouth theme and an `amogus-beep`
  boot jingle ([`boot.nix`](../../nixos/boxes/kelder/boot.nix)).

## Notable config files

- [`nixos/boxes/kelder/default.nix`](../../nixos/boxes/kelder/default.nix) — system, assignments, tunnel, NAT, containers.
- [`nixos/boxes/kelder/boot.nix`](../../nixos/boxes/kelder/boot.nix) — Plymouth theme + boot beep.
- [`nixos/boxes/kelder/containers/`](../../nixos/boxes/kelder/containers) — the two container definitions.
- [`nixos/boxes/kelder/dns_update.py`](../../nixos/boxes/kelder/dns_update.py) — Cloudflare DDNS script.
