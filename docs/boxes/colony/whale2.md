# whale2

A podman/OCI host on colony dedicated to game servers (kept off `shill` so the
container churn and resource use stay isolated).

- **Source:** [`nixos/boxes/colony/vms/whale2/`](../../../nixos/boxes/colony/vms/whale2)
  (`default.nix`, `valheim.nix`, `minecraft/`, `enshrouded.nix`)
- **nixpkgs:** `mine`
- **Host:** VM on `colony`

## Role

- Runs OCI containers via **podman** (`virtualisation.oci-containers`, netavark
  backend) on a dedicated `colony` bridge network (`oci`) with both IPv4 and
  IPv6, so each game server gets its own routable address.
- Game servers configured in-repo: **Valheim**, **Minecraft** (several worlds —
  see `extraAssignments`: `simpcraft`, `simpcraft-staging`, `kevcraft`,
  `kinkcraft`, `graeme`), and **Enshrouded** (currently commented out).
- `/var/lib/containers` is an XFS data disk (project quotas).

## Networking

- `vms` interface with `routing` / `internal` (alt name `oci`) assignments.
- An `oci` bridge carrying the `prefixes.oci` v4/v6 ranges; per-game addresses
  are handed out via `extraAssignments` (`valheim-oci`, `simpcraft-oci`, …) and
  exposed to the internet through `estuary`'s port forwards.
- Firewall trusts the `oci` interface and forwards `vms → oci`.
