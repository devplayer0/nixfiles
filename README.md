# nixfiles

Personal Nix flake managing every box I run: hosted servers, home
infrastructure, routers, a remote site, VPSes and personal workstations. It is
built around a **custom module system** layered on top of NixOS and
home-manager rather than the stock per-host `nixosConfigurations` pattern.

For the module-system internals, see [`docs/architecture.md`](docs/architecture.md); for day-to-day
commands, deployment and secrets, see [`docs/deployment.md`](docs/deployment.md). This README is the
map of **what is actually deployed**; the per-box details live under [`docs/`](docs) (start at
[`docs/README.md`](docs/README.md)).

> **Note:** This documentation (the README and everything under `docs/`) is a
> work in progress and was **agent-generated** from the repository. It may be
> incomplete or out of date — treat the Nix configuration as the source of truth.

## The boxes at a glance

Boxes are grouped by deployment/location. Each group has its own directory
under `docs/` with a `README.md` overview and one page per box.

| Group | What it is |
| --- | --- |
| [**colony**](docs/sites/colony) | Hosted dedicated server in Amsterdam (`ams1`). A VM host running the public-facing infrastructure: routing, web, git, media, object storage, chat, game servers. |
| [**home**](docs/sites/home) | Home network: a VM host (`palace`), the home routers, storage, Home Assistant, and a workstation — plus the hand-configured switches and wireless APs tying it together. |
| [**remote**](docs/remote) | Edge VPSes (`britway`, `britnet`) and the remote `kelder` site. |
| [**mobile**](docs/mobile) | The `tower` laptop. |

The custom installer image is documented at [`docs/misc/installer.md`](docs/misc/installer.md).
The general topics — the module system, network and deployment — live next to the index:
[`docs/architecture.md`](docs/architecture.md), [`docs/networking.md`](docs/networking.md) and
[`docs/deployment.md`](docs/deployment.md). The generated custom-module option reference is at
[`docs/reference/nixos-options.md`](docs/reference/nixos-options.md).

The high-level site diagrams and box hierarchy live in [`docs/README.md`](docs/README.md).
Networking is largely defined by per-box `assignments` plus the AS211024 L2 VXLAN mesh; see
[`docs/networking.md`](docs/networking.md) for the full picture and
[`docs/architecture.md`](docs/architecture.md) for the implementation mechanics.

## Repo layout

```
README.md           <- you are here
nixos/
  boxes/            per-box configuration
    colony/         colony host + its VMs (vms/) + shill's containers
    home/           palace host + its VMs, routing-common, plus stream, castle
    britway/        London VPS
    kelder/         remote box + its containers
    tower/          laptop
    britnet.nix     Birmingham VPS
  installer.nix     installer-image configuration
  modules/          shared NixOS modules (my.* options); registered in _list.nix
home-manager/       home-manager modules + configs
lib/                lib.my helpers, constants (lib.my.c), net/dns helpers
pkgs/               custom packages (overlays.default)
secrets/            age-encrypted secrets (ragenix)
devshell/           devshell commands (build/deploy/check/ssh helpers)
ci/                 CI helpers (binary-cache push, docs generators)
docs/               deployment documentation (index at docs/README.md)
```

A box is wired into the flake by adding its config file to the `configs` list
in `flake.nix`. See [the top-level evaluation](docs/architecture.md#the-top-level-evaluation) for
how `evalModules` turns these into `nixosConfigurations`, `homeConfigurations` and `deploy` nodes.
