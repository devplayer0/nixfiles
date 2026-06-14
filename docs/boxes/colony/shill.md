# shill

The colony **NixOS container host**. Most colony applications run as
systemd-nspawn containers on `shill`.

- **Source:** [`nixos/boxes/colony/vms/shill/`](../../../nixos/boxes/colony/vms/shill)
  (`default.nix`, `containers-ext.nix`, `hercules.nix`, `containers/`)
- **nixpkgs:** `mine`
- **Host:** VM on `colony` (large: 12 cores, 40 GiB RAM)

## Role

- Runs the colony NixOS containers via `my.containers.instances`, each attached
  to the `ctrs` bridge with its own address.
- Provides shared data volumes to those containers via bind mounts from
  LVM-backed disks: `/mnt/media` (→ `middleman`, `jackflix`), `/mnt/minio` and
  `/mnt/nix-cache` (→ `object`).
- Acts as the router between the `vms` network and the `ctrs` container network
  (sends RAs on `ctrs`, routes Tailscale prefixes via `waffletail` and the
  `qclk` prefix via `qclk`). Includes an nftables `ct mark` hack to make
  internal DNAT return paths work.
- Tuned sysctls for high connection counts / torrent traffic; netdata.

## Containers

Defined in [`shill/containers/`](../../../nixos/boxes/colony/vms/shill/containers)
and wired up in `shill`'s `my.containers.instances`:

| Container | Role |
| --- | --- |
| [`middleman`](middleman.md) | Front-end nginx reverse proxy, ACME, nginx-sso, librespeed |
| [`colony-psql`](colony-psql.md) | Shared PostgreSQL |
| [`vaultwarden`](vaultwarden.md) | Password manager |
| [`chatterbox`](chatterbox.md) | Matrix homeserver + bridges |
| [`toot`](toot.md) | Bluesky PDS (Mastodon disabled) |
| [`jackflix`](jackflix.md) | Media stack |
| [`object`](object.md) | MinIO / Harmonia / HedgeDoc / wastebin |
| [`waffletail`](waffletail.md) | Tailscale subnet router |
| [`qclk`](qclk.md) | Clock service |
| [`gam`](gam.md) | Game servers |

## Notes

- Container systems set `my.deploy.enable = false` (they are deployed as part of
  `shill`'s container profiles, not as standalone deploy nodes) and render via
  `my.asContainer`.
- `hercules.nix` configures Hercules CI agent bits;
  `containers-ext.nix` holds extra per-container host wiring.
