# sfh

The home **NixOS container host** ("smart from home" / home services).

- **Source:** [`nixos/boxes/home/palace/vms/sfh/`](../../../nixos/boxes/home/palace/vms/sfh)
  (`default.nix`, `containers/`)
- **Host:** VM on `palace`

## Role

- Runs the home NixOS containers via `my.containers.instances`, in the same way
  `shill` does on colony.
- Sits on the home network and connects to NVMe-oF storage (`cellar`) where
  needed.

## Containers

Defined in [`sfh/containers/`](../../../nixos/boxes/home/palace/vms/sfh/containers)
and imported from its `containers/default.nix`:

| Container | Role | Docs |
| --- | --- | --- |
| `hass` | Home Assistant | [hass.md](hass.md) |
| `unifi` | UniFi controller — **defined but currently commented out** of `containers/default.nix` | [unifi.md](unifi.md) |
