# hass

[Home Assistant](https://www.home-assistant.io/) — home automation.

- **Source:** [`sfh/containers/hass.nix`](../../../nixos/boxes/home/palace/vms/sfh/containers/hass.nix)
- **Host:** NixOS container on `sfh`

## Role

- Runs Home Assistant plus supporting services in the container. The `hass-cli`
  is wired up against the local server for convenience.
- Integrations/automations are configured here (see commit history for things
  like the "West Wood" integration).

## Networking

- `internal` assignment (alt name `hass-ctr`), plus a loopback assignment
  (`hass-ctr-lo`) used internally.
