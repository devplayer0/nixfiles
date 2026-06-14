# nixfiles

Personal Nix flake managing every machine I run: hosted servers, home
infrastructure, routers, a remote site, VPSes and personal workstations. It is
built around a **custom module system** layered on top of NixOS and
home-manager rather than the stock per-host `nixosConfigurations` pattern.

For day-to-day commands and a deeper explanation of the module system,
conventions and secrets, see [`AGENTS.md`](AGENTS.md). This README is the map of
**what is actually deployed**; the per-machine details live under [`docs/boxes/`](docs/boxes).

> **Note:** This documentation (the README and everything under `docs/`) is a
> work in progress and was **agent-generated** from the repository. It may be
> incomplete or out of date — treat the Nix configuration as the source of truth.

## The boxes at a glance

Machines are grouped by deployment/location. Each group has its own directory
under `docs/boxes/` with a `README.md` overview and one file per machine.

| Group | What it is | Docs |
| --- | --- | --- |
| **colony** | Hosted dedicated server in Amsterdam (`ams1`). A VM host running the public-facing infrastructure: routing, web, git, media, object storage, chat, game servers. | [`docs/boxes/colony/`](docs/boxes/colony) |
| **home** | Home network: a VM host (`palace`), the home routers, storage, Home Assistant, and personal desktops. | [`docs/boxes/home/`](docs/boxes/home) |
| **misc** | Everything else: edge VPSes (`britway`, `britnet`), the remote `kelder` site, the `tower` workstation, and the installer image. | [`docs/boxes/misc/`](docs/boxes/misc) |

## The "big machine" pattern

The larger sites (`colony`, `home`) all follow the same shape:

```
physical host (VM host)
├── VM ── thing impractical to containerise (router, storage, podman host, …)
├── VM ── container host ──┬── NixOS container ── application
│                          ├── NixOS container ──┬── application
│                          │                     ├── application
│                          │                     └── application
│                          └── …
└── VM ── …
```

- A **physical host** (`colony`, `palace`) does little itself beyond running
  **VMs** via the custom `my.vms` module (QEMU + systemd units, LVM-backed
  disks).
- **VMs** exist for things that are impractical to put in a container — kernel
  features, separate networking, podman/OCI workloads, foreign OSes.
- One VM is usually a **container host** (`shill` on colony, `sfh` on home; and
  `kelder` directly). It runs **NixOS containers** via the custom `my.containers`
  module (systemd-nspawn based, each with its own address on a bridge).
- **Most applications live in those NixOS containers.** A container isn't limited
  to a single application — it commonly hosts a **group of related applications**
  that belong together (e.g. `jackflix` runs Jellyfin, the *arr stack,
  Transmission, PhotoPrism and copyparty; `object` runs MinIO, Harmonia, HedgeDoc
  and wastebin). Each container is a first-class entry in `docs/boxes/`.

Networking between everything is largely defined by per-system `assignments`
(IPs/prefixes) plus an L2 VXLAN mesh (`my.vpns.l2`, AS211024) that ties the edge
routers together. See [`AGENTS.md`](AGENTS.md) for the mechanics.

## Repo layout

```
README.md           <- you are here
nixos/
  boxes/            per-machine configuration ("boxes")
    colony/         colony host + its VMs (vms/) + shill's containers
    home/           palace host + its VMs, plus stream, castle
    britway/        britnet.nix, kelder/, tower/, installer.nix …
  modules/          shared NixOS modules (my.* options); registered in _list.nix
home-manager/       home-manager modules + configs
lib/                lib.my helpers, constants (lib.my.c), net/dns helpers
pkgs/               custom packages (overlays.default)
secrets/            age-encrypted secrets (ragenix)
devshell/           devshell commands (build/deploy/check/ssh helpers)
docs/boxes/         per-machine documentation (colony/, home/, misc/)
```

A machine is wired into the flake by adding its box file to the `configs` list
in `flake.nix`. See [`AGENTS.md`](AGENTS.md#architecture) for how `evalModules`
turns these into `nixosConfigurations`, `homeConfigurations` and `deploy` nodes.
