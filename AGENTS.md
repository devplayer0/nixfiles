# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

`CLAUDE.md` at the repo root is a symlink to this file — edit `AGENTS.md`, not the symlink (some
tools refuse to write through a symlink and will error on `CLAUDE.md`).

**Prefer this file over agent memory.** When you learn something durable about this repo — a
convention, a workflow gotcha, a design rationale — record it here (or in a repo doc this file
points to, e.g. `docs/sites/home/switches.md`), not in agent memory. AGENTS.md is versioned and
shared; memory is not.

Keep this file lean: it should contain only rules, workflows, safety constraints and sharp gotchas
an agent needs before starting work. Detailed inventories, topology, service operation and design
rationale belong in the canonical document under `docs/`; summarize only the essential constraint
here and link to that document instead of maintaining a second copy.

Claude Code permissions live in two files: `.claude/settings.json` (versioned, shared — the
committed allow list of safe-to-auto-approve commands) and `.claude/settings.local.json` (personal,
gitignored — where interactive "always allow" grants accumulate). Put durable, generally-safe
commands in the shared file; leave one-off or workstation-specific grants in the local one.

## Overview

Personal Nix flake managing NixOS systems and home-manager configurations for a set of
**boxes**, never a "fleet". It is built around a **custom module
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
  VMs and containers). A container is **not** its own deploy node — it is generated as a
  `container-<name>` profile on its **host** node. So `deploy .#<host>` deploys the host's `system`
  profile and every one of its containers, whereas `deploy .#<host>.container-<name>` targets a
  single container (e.g. `deploy .#shill.container-middleman`). Pass `--boot` to stage a config as the boot default **without** live-switching
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
- `installer-shell` / `do-install <system>` — drive an install against a booted installer at
  `$INSTALLER`. For bringing up a new box end to end follow the guided procedure in
  [`docs/install-box.md`](docs/install-box.md).
- `update-nixpkgs` / `update-home-manager` — bump pinned inputs. For the full periodic upgrade
  (rebasing the `devplayer0` nixpkgs fork, stable-release bumps, kernel and release-metadata
  refreshes, version-gate sweep, input review) follow the guided procedure in
  [`docs/nixpkgs-upgrade.md`](docs/nixpkgs-upgrade.md).

Use the narrowest relevant evaluation while iterating: `check-system <host>` for a box config,
`nix eval .#nixfiles.config.nixos.allAssignments --json` for assignment generation, or
`nix build --no-link .#nixfiles.config.nixos.optionsDoc` for the option reference. Reserve
`nix flake check --no-build` for final broad validation or reproducing CI.
CI builds each attr of `.#ci.x86_64-linux` (systems, homes, packages, shell) and pushes to the
Harmonia binary cache; see `.gitea/workflows/ci.yaml` and `ci/push-to-cache.sh`. A separate
workflow (`.gitea/workflows/update-docs.yaml`) regenerates the network assignments, NixOS option
reference and live DNS reference under `docs/`.

For DNS lookups use **`drill`** (ldns) — `dig` isn't installed in this environment (it fails with
exit 127, which is easy to miss if stderr is redirected). E.g. `drill -Q @<resolver> <name> A`.

For privilege escalation use **`doas`**, not `sudo` — the boxes don't install `sudo` (it fails with
`command not found`). E.g. `doas ip link set <if> up`.

For ad-hoc packages prefer **`pkgs#<name>`** over `nixpkgs#<name>` (e.g. `nix run pkgs#python3`):
`pkgs` is a system registry alias for the same pinned nixpkgs the boxes are built from, so it
resolves from the local store instead of fetching a different channel.

## Architecture

The mechanics in this section have expanded human-readable write-ups under `docs/`:
`docs/architecture.md` (module system), `docs/networking.md` (assignments, topology, meshes) and
`docs/deployment.md` (deploy-rs, devshell, secrets, CI). This section stays the terse agent
version; consult those for depth.

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

For a human-readable map of what is actually deployed (per-box roles, services and networking),
see `README.md` and `docs/` (index at `docs/README.md`; box pages under `docs/sites/`,
`docs/remote/`, `docs/mobile/`). Keep these in sync when adding, removing or repurposing a box or
service. The network-assignment tables are consolidated in `docs/networking.md` (one per site,
CI-generated from `allAssignments` between `<!-- assignments: <site> -->` markers); box pages
link to that section. Write the prose and let the updater refresh the tables.

### Home routers (`nixos/boxes/home/routing-common`)
`river` and `stream` share `routing-common`, a function of an `index`; keep common HA behavior there
and box-specific WAN behavior in the respective box file. Client-facing gateway and DNS services
must use the floating VIPs. `routing-common` only declares the inert `wan-online.target`; each box
wires its own reachability mechanism. See `docs/networking.md#router-ha` and the router box pages
for the design and operational detail. Keep pair-wide behavior in `docs/networking.md`; router
pages should document only their WAN, platform and other box-specific responsibilities.

The easy-to-mix-up implementation details are that `lib.my.networkdAssignment` and
`lib.my.mkVLAN` live under `lib.my`, networkd snippet constants such as `networkd.noL3` live under
`lib.my.c`, and interface MTU belongs in the `.network`'s `linkConfig.MTUBytes`.

### Home switches (`jim` / `dave` / `brian`)
These switches are not managed by the flake, and changing them is out-of-band and hard to revert.
Read `docs/sites/home/switches.md` before WAN or VLAN work, always confirm before applying a switch
change, and keep the documented layout and `lib.my.c.home.vlans` in sync.

### Home wireless APs (`vibe` / `wave`)
These APs are not managed by the flake; only their DNS records are. Read and update
`docs/sites/home/aps.md` when changing an AP or its VLAN layout.

## Secrets

age-encrypted secrets in `secrets/`, managed with **ragenix**. Each module declares
`my.secrets.files.<name>` and `my.secrets.key` (the host pubkey to encrypt for). `secrets.nix`
(the ragenix rules file) is generated by reading every system's declared secrets and computing the
recipient key list (always including `.keys/dev.pub`). Edit secrets with the `ragenix` devshell
command, which supplies `.keys/dev.key` as the identity. The `.keys/` directory (dev + deploy
private keys) is required for editing secrets, deploying, and running dev VMs.

When a recipient list changes, re-encrypt selectively with `ragenix --rekey-one <file>` for each
affected secret. `ragenix --rekey` rewrites **every** secret in `secrets/`, burying the real change
in churn.

## Conventions

- Format with `nixpkgs-fmt` (`fmt`). 2-space indent, `inherit (...)` blocks at the top of `let` —
  prefer `inherit (lib) mkOption ...;` (and bare use) over qualifying inline as `lib.mkOption`.
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
- Keep docs and prose plain — avoid vague AI-tell filler. In particular use "layout"/"structure"
  rather than "shape", and "General" rather than "cross-cutting topics"; name things directly
  instead of reaching for umbrella words.
- For network connectivity, use the concrete term — "interface", "connection", "network
  attachment" or the network's name — rather than calling it a "leg".
- Call the systems **"boxes"**, never "machines" or "fleet", except where "machine" is part of a
  command, option or upstream technical term such as QEMU's machine type.
- Commit subjects follow `area/scope: Capitalized summary` (e.g. `nixos/home: ...`); keep logically
  distinct changes in separate commits. Aim for 50-character subjects and do not exceed 72
  characters. Hard-wrap commit body lines at 72 characters; Git preserves an unwrapped `-m`
  argument as one long line, so include literal line breaks or use a commit-message file. Before
  reporting a commit, inspect `git show -s --format=%B HEAD` and amend it if any line exceeds 72
  characters. A concise body describing the change and its rationale is welcome when the subject
  alone does not provide enough context — keep it to the essentials rather than restating the diff.
  `Co-Authored-By` is the only trailer used here; do **not** add a `Claude-Session` link (or any
  other session/tooling trailer).
- **"Logically distinct" means unrelated** — two different applications, two boxes that have nothing
  to do with each other, a drive-by fix that happens to sit in a file you were editing anyway. One
  piece of work stays in one commit even when it touches a config, several docs and a switch: if the
  parts only make sense together, splitting them just makes each half unreviewable. Err towards one
  commit and split when a reader would ask why two things arrived together.

## Documentation

Human-readable docs live under `docs/` (index: `docs/README.md`). Box pages are under
`docs/sites/<site>/`, `docs/remote/`, `docs/mobile/`. A box that itself hosts sub-systems
(containers/nested VMs) gets a **directory named for it** with a `README.md` and the child pages
beneath it (e.g. `shill/README.md` + `shill/containers/*.md`, `sfh/README.md`). When a site and its
physical box share a name, the site keeps the `README.md` and the box page stays alongside it (for
example `sites/colony/README.md` and `sites/colony/colony.md`).

**Box page layout** (match the existing pages): H1 + a one-line intro; a short bullet list of
`Source` / `Host` / `nixpkgs`; an optional hardware inventory or VPS resource-allocation section;
`## Role`; `## Network assignments` that **links** to
[`networking.md#box-assignments`](docs/networking.md#box-assignments) (never inline the table); one
`##` section per topic; `## Notable config files` last. Keep non-hardware platform details in their
topical sections rather than moving them with the inventory. A box without static assignments still
gets the section with a short explanation instead of a generated-table link.

**Structure and layout:**
- Use **tables** for lists of structured items (BGP peers, forwarded ports, vhosts, containers,
  VMs, VLANs). Make the item **name the link**; don't add a separate `Page`/`Docs` column.
- Break up **long prose**: any bullet running past ~4 lines over several distinct facts becomes a
  `###` subheading (lead sentence + nested bullets). Don't leave walls of long bullets.
- Prefer durable concepts and named configuration identifiers over copying exact numbers that are
  tunable, generated or likely to drift. Exact values are appropriate when they are useful parts of
  the inventory or interface: VM resource allocations, hardware-fixed properties, network and
  protocol identifiers, exposed service ports, and safety or recovery values. Describe mutable
  implementation tunables by purpose and link to their source instead of duplicating the current
  value.
- **Per-site index pages** (`docs/sites/*/README.md`, `docs/remote/README.md`, and
  `docs/mobile/README.md`) use one table listing **boxes only**; don't repeat that inventory in a
  diagram. A box's containers / nested VMs are tabulated on that box's own page. The global
  `docs/README.md` is the exception: it may show them in high-level site diagrams, but should not
  add a second detailed inventory outside those diagrams.

**De-dup by ownership** — each fact has one home:
- Shared cross-box **fabric** (the AS211024 mesh, Tailscale/headscale topology, the BGP overview,
  the WireGuard-tunnel summary) is documented once in `docs/networking.md`; box pages give a
  one-line summary and link to it.
- Site-wide network definitions (prefixes, VLANs, router VIPs and router HA) also live in
  `docs/networking.md`; site pages summarize and link to the canonical section.
- **Box-specific** detail (a box's own BGP peers, the WireGuard tunnels it terminates, its
  services) lives on the box page; `networking.md` carries only a per-box summary that links out.
- Addresses represented by generated `assignments` or `extraAssignments` live only in the
  assignment tables; handwritten box and workload inventories link there instead of copying them.
  Addresses outside that data model (such as external peers or service endpoints) stay with the
  topic that owns them.

**Generated content:** the network-assignment tables in `networking.md`, the option reference
(`docs/reference/nixos-options.md`) and the live DNS tables (`docs/reference/dns.md`) are
CI-generated by the corresponding `update-docs-*` packages; the workflow supplies the DNS zones.
Don't hand-edit content between `<!-- ... -->` markers; write the surrounding prose or source
configuration and let the updater refresh the tables. The option-reference file is generated in
full.

**Keep docs current:** when you add, remove or repurpose a box or service, update its box page, the
relevant site-index `README.md`, and any affected prose in `networking.md` (the assignment/option
tables refresh via CI). This is the same "prefer docs over agent memory" rule from the top of this
file.
