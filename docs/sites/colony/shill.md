# shill

The colony NixOS container host — most colony applications run as
`systemd-nspawn` containers on this VM.

- **Source:** [`nixos/boxes/colony/vms/shill/`](../../../nixos/boxes/colony/vms/shill)
  (`default.nix`, `containers-ext.nix`, `containers/`)
- **Host:** VM on `colony` (large: 12 cores, 40 GiB RAM)
- **nixpkgs:** `mine`

## Role

- Runs the colony containers via `my.containers.instances`, each attached to
  the `ctrs` bridge with its own address. The containers are full NixOS
  systems rendered via `my.asContainer` and deployed as container profiles on
  `shill` (`my.deploy.enable = false` — they are not standalone deploy
  targets); the `my.containers` module wires up the nspawn units, `/persist`
  bind mounts and store binds.
- Provides shared data volumes to containers via bind mounts from LVM-backed
  disks: `/mnt/media` (→ `middleman` read-only, `jackflix` read-write),
  `/mnt/minio` and `/mnt/nix-cache` (→ `object`, both read-write).
- Routes between the `vms` network and the `ctrs` container network: sends RAs
  on `ctrs` (DNS = `estuary`'s base address) and routes the Tailscale prefixes
  via `waffletail` and the `qclk` prefix via `qclk`. Applies the shared
  `firewallForwards` DNAT for traffic addressed to `estuary`'s public IP, with
  an nftables `ct mark 0x1337` SNAT hack so forwarded return traffic stays
  symmetric.
- Tuned for high connection counts (larger conntrack table, wider ephemeral
  port range); netdata on 19999.

## Network assignments

<!-- assignments: shill -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| shill-vm-ctrs | ctrs | `10.100.2.1/24` | `2a0e:97c0:4d2:12::1/64` | ams1.int.nul.ie |  |
| shill-vm (ctr) | internal | `94.142.241.225/32` | `2a0e:97c0:4d2:11::2/64` | ams1.int.nul.ie |  |
| shill-vm-routing | routing | `10.100.1.2/24 gw 10.100.1.1` | — | ams1.int.nul.ie |  |
<!-- assignments-end -->

## Containers

Defined under
[`shill/containers/`](../../../nixos/boxes/colony/vms/shill/containers) and
wired up in `shill`'s `my.containers.instances`. Each has its own page:

| Container | IPv4 | IPv6 | Role | Page |
|---|---|---|---|---|
| `middleman` | `10.100.2.2` | `2a0e:97c0:4d2:12::2` | Reverse proxy, ACME, nginx-sso, librespeed | [middleman](shill/containers/middleman.md) |
| `vaultwarden` | `10.100.2.3` | `2a0e:97c0:4d2:12::3` | Password manager | [vaultwarden](shill/containers/vaultwarden.md) |
| `colony-psql` | `10.100.2.4` | `2a0e:97c0:4d2:12::4` | Shared PostgreSQL (14) | [colony-psql](shill/containers/colony-psql.md) |
| `chatterbox` | `10.100.2.5` | `2a0e:97c0:4d2:12::5` | Matrix Synapse + bridges | [chatterbox](shill/containers/chatterbox.md) |
| `jackflix` | `10.100.2.6` | `2a0e:97c0:4d2:12::6` | Media stack | [jackflix](shill/containers/jackflix.md) |
| `object` | `10.100.2.7` | `2a0e:97c0:4d2:12::7` | MinIO, Harmonia Nix cache, Sharry, HedgeDoc, wastebin | [object](shill/containers/object.md) |
| `toot` | `10.100.2.8` | `2a0e:97c0:4d2:12::8` | Bluesky PDS (Mastodon disabled) | [toot](shill/containers/toot.md) |
| `waffletail` | `10.100.2.9` | `2a0e:97c0:4d2:12::9` | Tailscale subnet router / exit node | [waffletail](shill/containers/waffletail.md) |
| `qclk` | `10.100.2.10` | `2a0e:97c0:4d2:12::a` | WireGuard management appliance | [qclk](shill/containers/qclk.md) |
| `gam` | `10.100.2.11` | `2a0e:97c0:4d2:12::b` | Terraria server | [gam](shill/containers/gam.md) |

### `jam`

A one-off: [`containers-ext.nix`](../../../nixos/boxes/colony/vms/shill/containers-ext.nix)
runs a raw `systemd-nspawn` container (not a `my.containers` instance, not
NixOS) with its root on the `jam` LV, private user namespaces and a `ve-jam`
veth. It gets the `jam` customer prefix (`prefixes.jam`, `jam-cust` in DNS)
and SSH is forwarded to it from `shill`'s public IP port 60022.

## Notes

- `nix.settings.substituters` is forced to just `https://cache.nixos.org` —
  `shill` sits next to the S3 cache on `object`, so it doesn't use it.
- [`hercules.nix`](../../../nixos/boxes/colony/vms/shill/hercules.nix)
  (Hercules CI agent + the `nix-cache-gc` timer for the S3 binary cache)
  exists but is **currently disabled**: the file is not imported by
  `shill/default.nix`.

## Notable config files

- [`nixos/boxes/colony/vms/shill/default.nix`](../../../nixos/boxes/colony/vms/shill/default.nix) — VM config, networkd, firewall, `my.containers.instances`.
- [`nixos/boxes/colony/vms/shill/containers/default.nix`](../../../nixos/boxes/colony/vms/shill/containers/default.nix) — container imports.
- [`nixos/boxes/colony/vms/shill/containers-ext.nix`](../../../nixos/boxes/colony/vms/shill/containers-ext.nix) — the `jam` nspawn container.
- [`nixos/modules/containers.nix`](../../../nixos/modules/containers.nix) — the `my.containers` module.
