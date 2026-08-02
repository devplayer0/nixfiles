# Deployment documentation

> **Note:** these pages are a work in progress and were **agent-generated** from the repository.
> They may be incomplete or out of date — treat the Nix configuration as the source of truth.

This directory documents the boxes managed by this flake: their roles, network assignments,
hierarchy, and the services they run. For the mechanics of the repo itself (conventions, module
system internals for contributors, agent guidance), see [`AGENTS.md`](../AGENTS.md).

The two big sites follow the pattern:

```
physical host (VM host)
└── VM (for things impractical to containerise)
    └── container host VM
        └── NixOS containers (one per application group)
```

Not every box fits this pattern, but **colony** and **home** are organised this way.

## General

- [`architecture.md`](architecture.md) — the custom module system, `my.*` namespace, multiple
  nixpkgs channels, shared module inventory.
- [`networking.md`](networking.md) — network assignments, domains, site topologies, router HA,
  the AS211024 L2 mesh, BGP, WireGuard, Tailscale.
- [`deployment.md`](deployment.md) — deploy-rs, devshell commands, secrets workflow, CI.
- [`reference/dns.md`](reference/dns.md) — generated forward and reverse DNS record reference.
- [`reference/nixos-options.md`](reference/nixos-options.md) — generated per-option reference for
  the custom `my.*` NixOS modules.

## Site: colony (Amsterdam)

Physical host and public-infrastructure hub — see [`sites/colony/README.md`](sites/colony/README.md).

```
colony (physical VM host, ams1)
├── estuary ── edge router: WAN, firewall/NAT, DNS, BGP (AS211024), WireGuard
├── shill ──── NixOS container host ──┬── middleman    (reverse proxy, ACME, nginx-sso, librespeed)
│                                     ├── vaultwarden  (password manager)
│                                     ├── colony-psql  (shared PostgreSQL)
│                                     ├── chatterbox   (Matrix Synapse + bridges)
│                                     ├── jackflix     (media stack)
│                                     ├── object       (MinIO, Harmonia Nix cache, Sharry, HedgeDoc, wastebin)
│                                     ├── toot         (Bluesky PDS; Mastodon disabled)
│                                     ├── waffletail   (Tailscale subnet router / exit node)
│                                     ├── qclk         (WireGuard management appliance)
│                                     ├── gam          (Terraria server)
│                                     └── jam          (raw nspawn customer container)
├── whale2 ─── podman/OCI host for game servers
├── git ────── Gitea + Gitea Actions runner
├── mail ───── Debian VM running mailcow (not NixOS)
└── darts ──── third-party/customer VM (opaque, not NixOS)
```

## Site: home

Redundant routers, VM host, storage, IoT containers and the workstation — see
[`sites/home/README.md`](sites/home/README.md). The hand-configured switch fabric (jim/dave/brian)
and the Digiweb WAN path are documented in [`sites/home/switches.md`](sites/home/switches.md).

```
h.nul.ie
├── palace (physical VM host — AMD, 100G, SR-IOV)
│   ├── river ── primary router VM (PPPoE / Digiweb WAN)
│   ├── cellar ─ NVMe-oF / SPDK storage target VM
│   └── sfh ──── container host VM ("shill from home")
│       ├── hass ── Home Assistant + Frigate + MQTT (container)
│       └── unifi ─ UniFi controller (container)
├── stream (physical secondary router — Virgin Media WAN)
└── castle (workstation / gaming desktop — netboot, NVMe-oF root)
```

## Remote boxes

The edge VPSes and remote `kelder` site are indexed in [`remote/README.md`](remote/README.md).

## Mobile boxes

The laptop is indexed in [`mobile/README.md`](mobile/README.md).

## Misc

- [`misc/installer.md`](misc/installer.md) — the custom NixOS installer image.

## A note on the assignment tables

The consolidated [`Box assignments`](networking.md#box-assignments) tables in
[`networking.md`](networking.md) (one per site, between `<!-- assignments: <site> -->` markers)
are **generated from the flake** (`nixos.allAssignments`) by `nix run .#update-docs-assignments` —
CI refreshes them on push. Individual box pages link to that section rather than carrying their
own table. Only the Notes column is hand-written; don't hand-edit the other cells.
