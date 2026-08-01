# shill

The colony NixOS container host — most colony applications run as
`systemd-nspawn` containers on this VM.

- **Source:** [`nixos/boxes/colony/vms/shill/`](../../../../nixos/boxes/colony/vms/shill)
  (`default.nix`, `containers-ext.nix`, `containers/`)
- **Host:** VM on `colony`
- **nixpkgs:** `mine`

## Role

### Container hosting

`my.containers.instances` runs the colony containers on the `ctrs` bridge. Each is a full NixOS
system rendered through `my.asContainer` and deployed as a profile on `shill`; containers are not
standalone deploy targets. The shared container module supplies the nspawn units, `/persist` and
store binds.

### Shared storage

LVM-backed host volumes are bind-mounted into the consumers: `/mnt/media` is read-only in
`middleman` and read-write in `jackflix`; `/mnt/minio` and `/mnt/nix-cache` are read-write in
`object`.

### Routing

`shill` routes between `vms` and `ctrs`, advertises `estuary` as DNS on `ctrs`, and routes Tailscale
through `waffletail` and the `qclk` prefix through `qclk`. It applies the shared `firewallForwards`
DNAT for `estuary`'s public IP; a connection-mark-based SNAT rule keeps replies symmetric.

### Host tuning

The box has a larger conntrack table and ephemeral-port range for high connection counts. Netdata
listens on port 19999.

## Network assignments

See the consolidated [network assignments](../../../networking.md#box-assignments) table (this box: `shill`).

## Containers

Defined under
[`shill/containers/`](../../../../nixos/boxes/colony/vms/shill/containers) and
wired up in `shill`'s `my.containers.instances`. The generated
[network assignments](../../../networking.md#box-assignments) table is the source of truth for
their current addresses. Each container has its own page:

| Container | Role |
|---|---|
| [`middleman`](containers/middleman.md) | Reverse proxy, ACME, nginx-sso, librespeed |
| [`vaultwarden`](containers/vaultwarden.md) | Password manager |
| [`colony-psql`](containers/colony-psql.md) | Shared PostgreSQL (14) |
| [`chatterbox`](containers/chatterbox.md) | Matrix Synapse + bridges |
| [`jackflix`](containers/jackflix.md) | Media stack |
| [`object`](containers/object.md) | MinIO, Harmonia Nix cache, Sharry, HedgeDoc, wastebin |
| [`toot`](containers/toot.md) | Bluesky PDS (Mastodon disabled) |
| [`waffletail`](containers/waffletail.md) | Tailscale subnet router / exit node |
| [`qclk`](containers/qclk.md) | WireGuard management appliance |
| [`gam`](containers/gam.md) | Terraria server |

### `jam`

A one-off: [`containers-ext.nix`](../../../../nixos/boxes/colony/vms/shill/containers-ext.nix)
runs a raw `systemd-nspawn` container (not a `my.containers` instance, not
NixOS) with its root on the `jam` LV, private user namespaces and a `ve-jam`
veth. It gets the `jam` customer prefix (`prefixes.jam`, `jam-cust` in DNS)
and SSH is forwarded to it from `shill`'s public IP port 60022.

## Notes

- `nix.settings.substituters` is forced to just `https://cache.nixos.org` —
  `shill` sits next to the S3 cache on `object`, so it doesn't use it.
- [`hercules.nix`](../../../../nixos/boxes/colony/vms/shill/hercules.nix)
  (Hercules CI agent + the `nix-cache-gc` timer for the S3 binary cache)
  exists but is **currently disabled**: the file is not imported by
  `shill/default.nix`.

## Notable config files

- [`nixos/boxes/colony/vms/shill/default.nix`](../../../../nixos/boxes/colony/vms/shill/default.nix) — VM config, networkd, firewall, `my.containers.instances`.
- [`nixos/boxes/colony/vms/shill/containers/default.nix`](../../../../nixos/boxes/colony/vms/shill/containers/default.nix) — container imports.
- [`nixos/boxes/colony/vms/shill/containers-ext.nix`](../../../../nixos/boxes/colony/vms/shill/containers-ext.nix) — the `jam` nspawn container.
- [`nixos/modules/containers.nix`](../../../../nixos/modules/containers.nix) — the `my.containers` module.
