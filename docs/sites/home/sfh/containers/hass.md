# hass

Home automation container: Home Assistant plus its supporting services (MQTT, camera restreaming,
Frigate NVR), running on [`sfh`](../README.md).

- **Source:** [`nixos/boxes/home/palace/vms/sfh/containers/hass.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/hass.nix)
- **Host:** NixOS container on `sfh`
- **nixpkgs:** `mine`

## Role

### Home Assistant

`services.home-assistant` uses declarative configuration (`configWritable = false`). It enables
the `esphome`, `zha`, `denonavr`, `webostv`, `androidtv_remote`, `heos`, `mqtt`, `wled`, `met` and
`google_translate` components, plus custom `alarmo`, `frigate`, `west_wood_club` and Irish Rail
integrations. A `hass-cli` wrapper uses a token from `my.secrets` to reach the local server.

- **mosquitto** — MQTT broker (anonymous local listener; port 1883 allowed, alongside HTTP).
- **go2rtc** — restreams the Reolink living-room camera (RTSP from `reolink-living-room`, on the
  `lo` network) and the office USB webcam (`/dev/video0` via ffmpeg).
- **Frigate** (`services.frigate`, `frigate.h.nul.ie` — the `frigate` alt name on the `hi`
  assignment) — records both restreamed cameras with a short retention policy; detection is
  disabled.
- External access is via `https://hass.nul.ie` through the `middleman` reverse proxy
  (`trusted_proxies`); internally it's `hass-ctr.h.nul.ie`.
- Not a deploy-rs target (`my.deploy.enable = false`) — it's rendered via `my.asContainer` and
  started by `sfh`'s `my.containers.instances`.

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `hass`).

## Storage

Frigate footage lives on a **separate HDD LV**: `palace` passes the `hdds/frigate` LVM LV to the
`sfh` VM, sfh mounts it at `/mnt/frigate`, and the container bind-mounts it at `/var/lib/frigate`
(read-write). This keeps recording churn off the NVMe-oF root.

## Devices

Passed through from `sfh` (USB host ports on `palace`):

- Nabu Casa Connect ZBT-1 Zigbee coordinator → `/dev/ttyUSB0` (used by `zha`).
- USB webcam → `/dev/video0` (go2rtc's `webcam_office` stream).
- The matching raw USB device node allowed through from `sfh`.

## Networking

MACVLAN interfaces created from `sfh`'s container NICs: `host0` on `lan-hi-ctrs` (the `hi` assignment,
alt name `frigate`, default gateway via the VIP) and `lan-lo` on `lan-lo-ctrs` (the `lo`
assignment, no gateway) — the `lo` interface reaches the IoT devices (the Reolink camera lives there).

## Notable config files

- [`nixos/boxes/home/palace/vms/sfh/containers/hass.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/hass.nix) —
  container system: Home Assistant, Frigate, mosquitto, go2rtc.
- [`nixos/boxes/home/palace/vms/sfh/default.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/default.nix) —
  the `sfh` side: bind mounts, MACVLAN wiring, `DeviceAllow`.
