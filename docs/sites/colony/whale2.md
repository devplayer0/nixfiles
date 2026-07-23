# whale2

The colony podman/OCI host, dedicated to game servers (kept off `shill` so
container churn and resource use stay isolated).

- **Source:** [`nixos/boxes/colony/vms/whale2/`](../../../nixos/boxes/colony/vms/whale2)
  (`default.nix`, `valheim.nix`, `minecraft/`, `enshrouded.nix`)
- **Host:** VM on `colony`
- **nixpkgs:** `mine`

## Role

- Runs OCI containers via podman (`virtualisation.oci-containers`, netavark
  backend, `firewall_driver = "none"` so podman doesn't fight `my.firewall`).
- Each game server gets its own routable address on the `colony` netavark
  network (defined in `/etc/containers/networks/colony.json`), which is backed
  by the `oci` interface and the `prefixes.oci` v4/v6 ranges; per-game
  addresses come from `extraAssignments` (`valheim-oci`, `simpcraft-oci`, …)
  and are passed to podman with `--network=colony:ip=…` (`lib.my.dockerNetAssignment`).
- `estuary` forwards the game ports in (see `firewallForwards`), so the
  servers are reachable on the public IP as well as directly over IPv6.
- `/var/lib/containers` is a dedicated XFS disk (project quotas).

## Network assignments

<!-- assignments: whale2 -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| whale-vm (oci) | internal | `94.142.241.226/32` | `2a0e:97c0:4d2:11::3/64` | ams1.int.nul.ie |  |
| whale-vm-oci | oci | `10.100.3.1/24` | `2a0e:97c0:4d2:13::1/64` | ams1.int.nul.ie |  |
| whale-vm-routing | routing | `10.100.1.3/24 gw 10.100.1.1` | — | ams1.int.nul.ie |  |
<!-- assignments-end -->

## Game servers

The OCI containers are documented here (they have no pages of their own).
Addresses are the per-container `extraAssignments` on the `oci` network;
ports are the public ones forwarded by `estuary`.

| Container | Address (v4 / v6 host) | Ports | Status |
|---|---|---|---|
| `valheim` | `10.100.3.2` / `2a0e:97c0:4d2:13::2` | `2456-2457`/udp | running |
| `simpcraft` | `10.100.3.3` / `2a0e:97c0:4d2:13::3` | `25565` tcp+udp | running |
| `simpcraft-staging` | `10.100.3.4` / `2a0e:97c0:4d2:13::4` | `25566` tcp | **disabled** (commented out) |
| `enshrouded` | `10.100.3.5` / `2a0e:97c0:4d2:13::5` | `15636-15637`/udp | **disabled** (`enshrouded.nix` not imported) |
| `kevcraft` | `10.100.3.6` / `2a0e:97c0:4d2:13::6` | `25567` tcp+udp | running |
| `kinkcraft` | `10.100.3.7` / `2a0e:97c0:4d2:13::7` | `25568` tcp+udp | running |
| `graeme` | `10.100.3.8` / `2a0e:97c0:4d2:13::8` | `25569` tcp+udp | running |

- **valheim** ([`valheim.nix`](../../../nixos/boxes/colony/vms/whale2/valheim.nix)) —
  `lloesche/valheim-server`, public server "amogus sus", world `simpland2`,
  allow-listed Steam IDs, password from agenix.
- **simpcraft** ([`minecraft/`](../../../nixos/boxes/colony/vms/whale2/minecraft)) —
  `itzg/minecraft-server` (self-built `git.nul.ie/dev/craftblock` image),
  Modrinth "Simpcraft" modpack, whitelist + ops, 8 GiB heap.
  **simpcraft-staging** is the same setup pinned to an older pack version,
  currently commented out.
- **kevcraft** — vanilla Minecraft 1.20.1, 4 GiB heap, extra op.
- **kinkcraft** — same Simpcraft modpack as `simpcraft`, 6 GiB heap.
- **graeme** — vanilla Minecraft on hard difficulty with its own whitelist.
- **enshrouded** ([`enshrouded.nix`](../../../nixos/boxes/colony/vms/whale2/enshrouded.nix)) —
  `sknnr/enshrouded-dedicated-server` ("UWUshrouded"); the file exists but is
  commented out of `whale2`'s `imports`, so the server is down (its forwards
  and DNS records remain).

The Minecraft containers share one whitelist/ops list and agenix env file
(`whale2/simpcraft.env`, which also carries the RCON password).

## Backups

A local borg job (`services.borgbackup.jobs.simpcraft`) archives the
`simpcraft` world every ~15 minutes (offset from the usual 5-minute autosave
ticks) into `/var/lib/containers/backup/simpcraft`, using `mcrcon` to
`save-off`/`save-on` around each run. Retention is short (12 h + 48 hourly) —
this is for quick world rollback, not disaster recovery (the `oci` LV itself
is covered by `colony`'s `borgthin`).

## Notable config files

- [`nixos/boxes/colony/vms/whale2/default.nix`](../../../nixos/boxes/colony/vms/whale2/default.nix) — VM config, podman/netavark setup, `extraAssignments`.
- [`nixos/boxes/colony/vms/whale2/valheim.nix`](../../../nixos/boxes/colony/vms/whale2/valheim.nix) — Valheim server.
- [`nixos/boxes/colony/vms/whale2/minecraft/default.nix`](../../../nixos/boxes/colony/vms/whale2/minecraft/default.nix) — the Minecraft servers + world backup job.
- [`nixos/boxes/colony/vms/whale2/enshrouded.nix`](../../../nixos/boxes/colony/vms/whale2/enshrouded.nix) — Enshrouded server (disabled, not imported).
