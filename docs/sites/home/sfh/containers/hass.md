# hass

Home automation container: Home Assistant plus its supporting services (MQTT, camera restreaming,
Frigate NVR), running on [`sfh`](../../sfh.md).

- **Source:** [`nixos/boxes/home/palace/vms/sfh/containers/hass.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/hass.nix)
- **Host:** NixOS container on `sfh`

## Role

- **Home Assistant** (`services.home-assistant`) — declarative config (`configWritable = false`),
  components `esphome`, `zha`, `denonavr`, `webostv`, `androidtv_remote`, `heos`, `mqtt`, `wled`,
  `met`, `google_translate`; custom components `alarmo`, `frigate`, `west_wood_club`; a custom
  Irish Rail sensor (Glenageary ↔ Dublin Connolly). A `hass-cli` wrapper is on the box, wired to
  the local server with a token from `my.secrets`.
- **mosquitto** — MQTT broker (anonymous local listener; port 1883 allowed, alongside HTTP).
- **go2rtc** — restreams the Reolink living-room camera (RTSP from `reolink-living-room`, on the
  `lo` leg) and the office USB webcam (`/dev/video0` via ffmpeg).
- **Frigate** (`services.frigate`, `frigate.h.nul.ie` — the `frigate` alt name on the `hi`
  assignment) — records both restreamed cameras with 1-day retention; detection is disabled.
- External access is via `https://hass.nul.ie` through the `middleman` reverse proxy
  (`trusted_proxies`); internally it's `hass-ctr.h.nul.ie`.
- Not a deploy-rs target (`my.deploy.enable = false`) — it's rendered via `my.asContainer` and
  started by `sfh`'s `my.containers.instances`.

## Network assignments

<!-- assignments: hass -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| hass-ctr (frigate) | hi | `192.168.68.103/22 gw 192.168.71.254` | `2a0e:97c0:4d0:1::5:3/64` | h.nul.ie |  |
| hass-ctr-lo | lo | `192.168.72.103/21` | `2a0e:97c0:4d0:2::5:3/64` | h.nul.ie |  |
<!-- assignments-end -->

## Storage

Frigate footage lives on a **separate HDD LV**: `palace` passes the `hdds/frigate` LVM LV to the
`sfh` VM, sfh mounts it at `/mnt/frigate`, and the container bind-mounts it at `/var/lib/frigate`
(read-write). This keeps recording churn off the NVMe-oF root.

## Devices

Passed through from `sfh` (USB host ports on `palace`):

- Nabu Casa Connect ZBT-1 Zigbee coordinator → `/dev/ttyUSB0` (used by `zha`).
- USB webcam → `/dev/video0` (go2rtc's `webcam_office` stream).
- `/dev/bus/usb/001/002` (raw USB device node).

## Networking

MACVLAN legs created from `sfh`'s container NICs: `host0` on `lan-hi-ctrs` (the `hi` assignment,
alt name `frigate`, default gateway via the VIP) and `lan-lo` on `lan-lo-ctrs` (the `lo`
assignment, no gateway) — the `lo` leg reaches the IoT devices (the Reolink camera lives there).

## Notable config files

- [`nixos/boxes/home/palace/vms/sfh/containers/hass.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/hass.nix) —
  container system: Home Assistant, Frigate, mosquitto, go2rtc.
- [`nixos/boxes/home/palace/vms/sfh/default.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/default.nix) —
  the `sfh` side: bind mounts, MACVLAN wiring, `DeviceAllow`.
