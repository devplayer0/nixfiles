# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

`CLAUDE.md` at the repo root is a symlink to this file — edit `AGENTS.md`, not the symlink (some
tools refuse to write through a symlink and will error on `CLAUDE.md`).

**Prefer this file over agent memory.** When you learn something durable about this repo — a
convention, a workflow gotcha, a design rationale — record it here (or in a repo doc this file points
to, e.g. `home-switches.md`), not in agent memory. AGENTS.md is versioned and shared; memory is not.

## Overview

Personal Nix flake managing NixOS systems and home-manager configurations for a set of
machines — always called **"boxes"**, never "fleet". It is built around a **custom module
system** layered on top of NixOS/home-manager, not the stock flake `nixosConfigurations` pattern.

## Commands

This repo provides a `numtide/devshell` (entered via `direnv` / `use flake`). The shell defines
named commands — prefer them over raw `nix` invocations. Run a bare command name with no args to
see its help, or browse `devshell/commands.nix` / `devshell/install.nix` / `devshell/vm-tasks.nix`.

Common ones:
- `fmt` — format Nix with `nixpkgs-fmt` (the canonical formatter here).
- `build-system <host> [nix args]` — build a NixOS system's `toplevel`.
- `build-n-switch <args>` — wraps `doas nixos-rebuild --flake .`.
- `build-home <name>` / `home-switch` — build / switch a home-manager config.
- `run-vm <host>` — build & boot a system as a dev VM (installs `.keys/dev.key` into the VM).
- `build-iso` / `build-kexec` / `build-netboot <host>` — alternate build outputs via `config.my.buildAs.*`.
- `check-system <host> [nix args]` — evaluate a system (catches eval errors without a full build).
  **Prefer this over `build-system` to validate a config change** — evaluation surfaces module/option
  errors quickly and cheaply; only do a full build when you specifically need the built artifact.
- `deploy <host>` and `deploy-multi <hosts...>` — deploy-rs deployment (uses `.keys/deploy.key`, `--skip-checks`).
  Pass the flake-qualified node, e.g. `deploy .#git`. The deploy node name is **always** the system
  name (`deploy-rs.nix` keys nodes directly off `nixos.systems` / `home-manager.homes`); a system is
  only a deploy target when `config.my.deploy.enable` is true (defaults true; auto-disabled for dev
  VMs and containers). Pass `--boot` to stage a config as the boot default **without** live-switching
  (`deploy --boot .#<host>`) — the box keeps running its current generation until it reboots. Use this
  when a live `switch` would break connectivity mid-change (e.g. a router's WAN VLAN rework), then
  reboot to cut over.
- `ssh-machine <name> [cmd]` — SSH to a NixOS system or home-manager config by name. Resolves the
  target and ssh options (identity, port) from its deploy-rs node, so it needs `my.deploy.enable`
  (same gate as `deploy`). Boxes default to the `fish` login shell, so pipe multi-statement remote
  scripts through `bash` (e.g. `ssh-machine <name> bash -s < script.sh`) rather than `&&`/`for`.
  If outbound SSH hangs at the publickey step (flaky `ssh-agent`), disable the agent for the call:
  `SSH_AUTH_SOCK= ssh-machine …` (or add `-o IdentityAgent=none` to a raw `ssh`).
- `ragenix` — edit age secrets using `.keys/dev.key` as identity (see Secrets).
- `repl` — `nix repl .#`.
- `update-nixpkgs` / `update-home-manager` — bump pinned inputs.

Check everything (what CI runs): `nix flake check --no-build`.
CI builds each attr of `.#ci.x86_64-linux` (systems, homes, packages, shell) and pushes to the
Harmonia binary cache; see `.gitea/workflows/ci.yaml` and `ci/push-to-cache.sh`.

## Architecture

### The custom module system
`flake.nix` does **not** call `nixosSystem` per host directly. Instead it `evalModules` over
`./nixos`, `./home-manager`, `./deploy-rs.nix`, and the per-host files listed in the `configs`
list in `flake.nix`. That evaluation produces a top-level config (`self.nixfiles`) from which the
real flake outputs are derived:
- `nixos.systems.<name>` → `nixosConfigurations.<name>`
- `home-manager.homes.<name>` → `homeConfigurations.<name>`
- `nixos.modules` / `home-manager.modules` → `nixosModules` / `homeModules`
- `deploy-rs.rendered` → `deploy`

`nixos/default.nix` and `home-manager/default.nix` define the `systemOpts` / `homeOpts` submodules
and the `mkSystem` / `mkHome` functions that actually invoke `eval-config.nix` /
`homeManagerConfiguration`. **To add a new host:** create a box file that sets
`nixos.systems.<name> = { ... }`, then add its path to the `configs` list in `flake.nix`.

### Multiple nixpkgs channels
Four pkgs sets are threaded everywhere as `pkgsFlakes` / `pkgs'` (and `hmFlakes` for home-manager):
`unstable`, `stable`, `mine` (a personal nixpkgs fork), `mine-stable`. Each system/home picks its
channel via `nixpkgs` / `home-manager` / `hmNixpkgs` options (e.g. `nixpkgs = "mine-stable"`).
Modules receive `pkgs'` = an attrset of all channels for the current system.

### `lib.my` and the `my` option namespace
`lib/default.nix` extends `lib` with a `my` attrset (helpers like `mkOpt'`, `mkBoolOpt'`,
`mkDefault'`, `inlineModule'`, `mkDefaultSystemsPkgs`, `homeStateVersion`). It also pulls in:
- `lib.my.net` — network/CIDR helpers from the `libnetRepo` input. Used heavily for IP math.
- `lib.my.c` — shared constants from `lib/constants.nix` (UIDs/GIDs, kernel package selection,
  nginx snippets, per-network domains/prefixes, etc.). Reuse these rather than hardcoding.
- `lib.my.dns` — DNS helpers (`lib/dns.nix`).

Custom modules add options under the `my.*` namespace (e.g. `my.secrets`, `my.build`,
`my.tmproot`, `my.server`). Use `mkOpt'`/`mkBoolOpt'` for option declarations to match style.

### Modules and module lists
Module sets are registered in `nixos/modules/_list.nix` and `home-manager/modules/_list.nix`
(name → path), which become `nixos.modules` / `home-manager.modules` and are applied to every
system/home. To add a shared module, drop the file in `nixos/modules/` (or `home-manager/modules/`)
and add an entry to the relevant `_list.nix`.

### Network assignments
Each system declares `assignments.<name>` (in its `nixos.systems.<host>` block) with IPv4/IPv6
addresses, gateways, domains, MTU, etc. These are aggregated into `allAssignments` (passed to every
module) and there is an assertion that fails on duplicate IPs. Host networking
(`networking.hostName`, `domain`) defaults from the `internal` assignment.

### Hosts / "boxes"
Per-host configs live under `nixos/boxes/<host>` (some are single `.nix` files, some directories
with nested VMs/containers under e.g. `colony/vms`). Many "systems" are VMs or containers managed
via the `vms` / `containers` modules and the `l2mesh` VXLAN module.

### Home routers (`nixos/boxes/home/routing-common`)
The two home routers, `river` and `stream`, share `routing-common`, which is a **function of an
`index`** (`import ../../routing-common 0` for river, `1` for stream). The index derives per-box
addresses, keepalived VRRP priorities/state, DNS `ns` numbering, etc., so the two boxes are an
active/backup HA pair from one definition. They differ where hardware/uplink differ: `stream` has a
DHCP WAN, `river` runs PPPoE (`services.pppd`, Digiweb) — box-specific bits live in the respective
box file, not `routing-common`.

- **HA is VRRP (`keepalived`).** Per-VLAN floating **VIPs** (`lib.my.c.home.vips`) are what clients
  use as both gateway *and* DNS server. `kea` (DHCP) and `radvd` (RAs; started only on the master)
  hand out the VIP, and `pdns-recursor` binds the VIPs (with `net.ipv*.ip_nonlocal_bind` so the
  backup can pre-bind). Point client-facing services at the VIP, not a box's real address, so
  failover follows the master instead of relying on client resolver timeouts.
- **`wan-online.target`** is a shared abstract target meaning "the public WAN/IPv4 route is up".
  `routing-common` only declares it; each box wires *how it is reached* (`stream`: a oneshot that
  waits for the DHCP default route; `river`: the pppd `ip-up`/`ip-down` hooks). Services that need
  the WAN attach **to** it via `wantedBy` + `partOf` + `after` (not `requires`/`wants`), so an empty
  target is never pulled in and prematurely activated, and they re-load on WAN flap.
- networkd helpers used heavily here: `lib.my.networkdAssignment` and `lib.my.mkVLAN` live under
  **`lib.my`**, while networkd snippet constants like `networkd.noL3` live under **`lib.my.c`** —
  easy to mix up. Set an interface MTU via the `.network`'s `linkConfig.MTUBytes` (`[Link]`), not
  `netdevConfig` (`[NetDev]` rejects `MTUBytes`).

### Home switches (`jim` / `dave` / `brian`)
The home boxes and the Digiweb WAN hang off hand-configured switches that are **not** managed by
this flake: `jim` and `dave` (MikroTik, RouterOS) and `brian` (Ubiquiti, UniFi). The full topology,
VLAN map, and the ONT/WAN path live in **`home-switches.md`** at the repo root — read it before
touching anything WAN/VLAN-related, and update it when the switch layout changes.
- **Access:** the switches resolve by **short hostname** on the home network (the routers serve
  their records in the home zone — `routing-common/dns.nix`: `jim`/`dave`/`brian`). From a home box,
  SSH to the MikroTiks as `admin`/`admin` (e.g. `ssh admin@jim`); `brian` is configured via the
  UniFi controller, not a CLI.
- **Changing switch config is out-of-band and hard to revert — always confirm before applying:**
  print the affected menu, make the change, then re-verify. The nix config and the switches must
  agree on VLAN numbering (e.g. `lib.my.c.home.vlans`), so a switch-side change usually pairs with a
  box change; `home-switches.md` documents the switch layout and per-switch config for the WAN design.

## Secrets

age-encrypted secrets in `secrets/`, managed with **ragenix**. Each module declares
`my.secrets.files.<name>` and `my.secrets.key` (the host pubkey to encrypt for). `secrets.nix`
(the ragenix rules file) is generated by reading every system's declared secrets and computing the
recipient key list (always including `.keys/dev.pub`). Edit secrets with the `ragenix` devshell
command, which supplies `.keys/dev.key` as the identity. The `.keys/` directory (dev + deploy
private keys) is required for editing secrets, deploying, and running dev VMs.

## Conventions

- Format with `nixpkgs-fmt` (`fmt`). 2-space indent, `inherit (...)` blocks at the top of `let`.
  **Ask before running `fmt`** — some files aren't canonically formatted, so `fmt` can reindent a
  whole file and bury a logical change in whitespace churn. Match the surrounding style by hand and
  leave formatting to the user unless they ask.
- Comment where it genuinely aids understanding, but not for trivial/obvious code — match the file's
  existing (fairly sparse) comment density. When adding something general, comment its general
  purpose, not the specific change or one-off reason it was introduced for.
- Prefer `lib.my` helpers (`mkOpt'`, `mkBoolOpt'`, `mkDefault'`) and `lib.my.c` constants over
  reimplementing.
- New shared functionality → a module in `*/modules/` + entry in `_list.nix`, options under `my.*`.
- New host → box file under `nixos/boxes/` + entry in the `configs` list in `flake.nix`.
- Custom packages live in `pkgs/` and are registered in `pkgs/default.nix`; the overlay is exposed
  as `overlays.default`.
- In prose and commit messages, quote code-like identifiers (commands, options, paths, package and
  attribute names) in backticks.
- Call the machines **"boxes"**, never "fleet".
- Commit subjects follow `area/scope: Capitalized summary` (e.g. `nixos/home: ...`); keep logically
  distinct changes in separate commits.
