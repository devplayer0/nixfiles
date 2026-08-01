# whale2

The colony podman/OCI host, dedicated to game servers (kept off `shill` so
container churn and resource use stay isolated).

- **Source:** [`nixos/boxes/colony/vms/whale2/`](../../../nixos/boxes/colony/vms/whale2)
  (`default.nix`, `valheim.nix`, `minecraft/`, `enshrouded.nix`)
- **Host:** VM on `colony`
- **nixpkgs:** `mine`

## Role

### Container runtime

OCI containers run under podman (`virtualisation.oci-containers`) with the netavark backend and
`firewall_driver = "none"`, leaving firewall management to `my.firewall`.

### Routable game servers

Each server gets an address from `extraAssignments` (`valheim-oci`, `simpcraft-oci`, …) on the
`colony` netavark network. That network is backed by the `oci` interface and `prefixes.oci` v4/v6
ranges; `lib.my.dockerNetAssignment` supplies the address through `--network=colony:ip=…`.
`estuary` forwards the public game ports, while IPv6 reaches the containers directly.

### Storage

`/var/lib/containers` is a dedicated XFS disk with project quotas.

## Network assignments

See the consolidated [network assignments](../../networking.md#box-assignments) table (this box: `whale2`).

## Game servers

The OCI containers are documented here (they have no pages of their own).
Their per-container `extraAssignments` on the `oci` network are listed in the generated
[network assignments](../../networking.md#box-assignments) table. Ports below are the public ones
forwarded by `estuary`.

| Container | Ports | Status |
|---|---|---|
| `valheim` | `2456-2457`/udp | running |
| `simpcraft` | `25565` tcp+udp | running |
| `simpcraft-staging` | `25566` tcp | **disabled** (commented out) |
| `enshrouded` | `15636-15637`/udp | **disabled** (`enshrouded.nix` not imported) |
| `kevcraft` | `25567` tcp+udp | running |
| `kinkcraft` | `25568` tcp+udp | running |
| `graeme` | `25569` tcp+udp | running |

- **valheim** ([`valheim.nix`](../../../nixos/boxes/colony/vms/whale2/valheim.nix)) —
  `lloesche/valheim-server`, public server "amogus sus", world `simpland2`,
  allow-listed Steam IDs, password from agenix.
- **simpcraft** ([`minecraft/`](../../../nixos/boxes/colony/vms/whale2/minecraft)) —
  `itzg/minecraft-server` (self-built `git.nul.ie/dev/craftblock` image),
  Modrinth "Simpcraft" modpack, whitelist + ops.
- **simpcraft-staging** — the same setup pinned to an older pack version, currently commented out.
- **kevcraft** — vanilla Minecraft 1.20.1, extra op.
- **kinkcraft** — same Simpcraft modpack as `simpcraft`.
- **graeme** — vanilla Minecraft on hard difficulty with its own whitelist.
- **enshrouded** ([`enshrouded.nix`](../../../nixos/boxes/colony/vms/whale2/enshrouded.nix)) —
  `sknnr/enshrouded-dedicated-server` ("UWUshrouded"); the file exists but is
  commented out of `whale2`'s `imports`, so the server is down (its forwards
  and DNS records remain).

The Minecraft containers share one whitelist/ops list and agenix env file
(`whale2/simpcraft.env`, which also carries the RCON password).

## Backups

A local borg job (`services.borgbackup.jobs.simpcraft`) archives the `simpcraft` world frequently,
offset from its autosave timer, into `/var/lib/containers/backup/simpcraft`. It uses `mcrcon` to
`save-off`/`save-on` around each run and keeps a short history for quick world rollback rather than
disaster recovery; the `oci` LV itself is covered by `colony`'s `borgthin`.

## Notable config files

- [`nixos/boxes/colony/vms/whale2/default.nix`](../../../nixos/boxes/colony/vms/whale2/default.nix) — VM config, podman/netavark setup, `extraAssignments`.
- [`nixos/boxes/colony/vms/whale2/valheim.nix`](../../../nixos/boxes/colony/vms/whale2/valheim.nix) — Valheim server.
- [`nixos/boxes/colony/vms/whale2/minecraft/default.nix`](../../../nixos/boxes/colony/vms/whale2/minecraft/default.nix) — the Minecraft servers + world backup job.
- [`nixos/boxes/colony/vms/whale2/enshrouded.nix`](../../../nixos/boxes/colony/vms/whale2/enshrouded.nix) — Enshrouded server (disabled, not imported).
