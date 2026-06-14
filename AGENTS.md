# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Overview

Personal Nix flake managing NixOS systems and home-manager configurations for a fleet of
machines (servers, home boxes, routers). It is built around a **custom module system** layered
on top of NixOS/home-manager, not the stock flake `nixosConfigurations` pattern.

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
- `deploy <host>` and `deploy-multi <hosts...>` — deploy-rs deployment (uses `.keys/deploy.key`, `--skip-checks`).
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

## Secrets

age-encrypted secrets in `secrets/`, managed with **ragenix**. Each module declares
`my.secrets.files.<name>` and `my.secrets.key` (the host pubkey to encrypt for). `secrets.nix`
(the ragenix rules file) is generated by reading every system's declared secrets and computing the
recipient key list (always including `.keys/dev.pub`). Edit secrets with the `ragenix` devshell
command, which supplies `.keys/dev.key` as the identity. The `.keys/` directory (dev + deploy
private keys) is required for editing secrets, deploying, and running dev VMs.

## Conventions

- Format with `nixpkgs-fmt` (`fmt`). 2-space indent, `inherit (...)` blocks at the top of `let`.
- Prefer `lib.my` helpers (`mkOpt'`, `mkBoolOpt'`, `mkDefault'`) and `lib.my.c` constants over
  reimplementing.
- New shared functionality → a module in `*/modules/` + entry in `_list.nix`, options under `my.*`.
- New host → box file under `nixos/boxes/` + entry in the `configs` list in `flake.nix`.
- Custom packages live in `pkgs/` and are registered in `pkgs/default.nix`; the overlay is exposed
  as `overlays.default`.
