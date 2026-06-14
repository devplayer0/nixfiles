# kelder

A host at a remote site ("kelder" = cellar/basement), linked back to the rest of
the other boxes over WireGuard. It is itself a **NixOS container host**.

- **Source:** [`nixos/boxes/kelder/`](../../../nixos/boxes/kelder)
  (`default.nix`, `boot.nix`, `containers/`, `plymouth/`)
- **Domain:** `hentai.engineer`

## Role

- **Site uplink:** connects to colony's `estuary` over **WireGuard**
  (`kelder` peer; see [estuary.md](../colony/estuary.md)), so the remote site is
  reachable through the colony edge. A periodic `dns_update.py` keeps DNS current.
- **Container host:** runs NixOS containers via `my.containers.instances`
  (`acquisition`, `spoder`).
- Custom boot/splash (`boot.nix`, Plymouth theme in `plymouth/`).

## Containers

| Container | Role | Docs |
| --- | --- | --- |
| `kelder-acquisition` | Media stack (Jellyfin + *arr + Transmission) | [kelder-acquisition.md](kelder-acquisition.md) |
| `kelder-spoder` | nginx web host | [kelder-spoder.md](kelder-spoder.md) |
