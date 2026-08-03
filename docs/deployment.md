# Deployment and workflows

How boxes get deployed, the devshell commands that drive everyday work, secrets, dev VMs, and
CI.

## deploy-rs

### Rendering

The top-level [`deploy-rs.nix`](../deploy-rs.nix) renders the flake's `deploy` output:

- It collects `nixos.systems` and `home-manager.homes` (mangling `@` in home names to
  `-at-`, since deploy-rs node names can't contain `@`). An assertion rejects name collisions
  between systems and homes.
- A system/home becomes a deploy node only when `configuration.config.my.deploy.enable` is
  true. The node config is the *definitions* of the box's `my.deploy.node` option, re-imported
  as a module so deploy-rs's submodule merging still applies.
- `autoRollback` and `magicRollback` are off globally; global `sshOpts` are
  `[ "-i" ".keys/deploy.key" ]` (set in [`flake.nix`](../flake.nix)).
- The result is passed through `lib.my.deploy-rs.filterOpts`, which strips nulls so unset
  options don't override deploy-rs defaults, and exposed as `deploy = deploy-rs.rendered`.

### Per-box nodes

The shared [`nixos/modules/deploy-rs.nix`](../nixos/modules/deploy-rs.nix) module provides
`my.deploy`:

- `my.deploy.enable` defaults to true, but is **automatically forced off for dev VMs and
  NixOS containers** (`my.build.isDevVM` / `boot.isContainer` — containers are deployed
  through their host instead, see below). The installer also disables it explicitly.
- Node defaults: `hostname` = the box's FQDN, `sshUser = "deploy"`, `user = "root"`,
  `sudo = "doas -u"` (or `sudo -u`), `sshOpts` = the box's first OpenSSH port. The module
  creates the `deploy` system user (bash shell, wheel, keys from `my.deploy.authorizedKeys`,
  which defaults to `.keys/deploy.pub`).

Generated profiles deploy in this order:

1. **`system`** activates `config.system.build.toplevel` with `switch-to-configuration switch`,
   applies the `/tmp` cwd and systemd-boot `loader.conf` workarounds, then prunes old generations.
   `keepGenerations` controls how much history is retained; zero disables pruning.
2. **`container-<name>`** activates each `my.containers.instances` entry into
   `/nix/var/nix/profiles/per-container/<name>/system`. With `hotReload` (the default), it reloads
   `systemd-nspawn@<name>` and restarts only a stopped container or one still running the dummy
   init; otherwise it restarts the unit. The same generation cleanup applies.

### Usage

- `deploy .#<host>` — the devshell's `deploy` is a wrapper that adds `--skip-checks`. Node
  names are the system names (`deploy .#git`).
- `deploy-multi <hosts...>` — loops `deploy` over several nodes (extra args via `$O`).
- `deploy --boot .#<host>` — stages the config as the boot default **without** live-switching
  (deploy-rs's `--boot` maps to the custom activation's `boot` phase, which also does the
  generation cleanup). Use it when a live `switch` would cut the box off mid-change (e.g. a
  router WAN rework), then reboot to cut over.
- `nix flake check` includes deploy-rs's own `deployChecks` for the whole `deploy` attrset.

#### `ssh-machine`

`ssh-machine <name> [cmd]` resolves `user@host` and the merged global/node `sshOpts` from
`.#deploy`, using the same `my.deploy.enable` gate and `@` → `-at-` mangling as `deploy`, then runs
`ssh`. Boxes default to `fish`, so pipe multi-statement remote scripts through `bash`, for example
`ssh-machine <name> bash -s < script.sh`. If a flaky agent stalls public-key authentication, use
`SSH_AUTH_SOCK= ssh-machine …`.

## Devshell commands

The repo ships a `numtide/devshell` ([`devshell/`](../devshell), entered via `direnv`). Run a
command with no arguments for its help. From
[`devshell/commands.nix`](../devshell/commands.nix):

| Command | What it does |
|---|---|
| `check-system <host> [nix args]` | Evaluates `.#nixosConfigurations."<host>".config.system.build.toplevel.drvPath` — catches module/option errors without building. Prefer this to validate a config change. |
| `build-system <host> [nix args]` | Builds the system's `toplevel` (extra args pass through to `nix build`). |
| `build-n-switch <args>` | `doas nixos-rebuild --flake .` (adds the repo as a git `safe.directory` for root first). |
| `build-home <name> [nix args]` | Builds `.#homeConfigurations."<name>".activationPackage`. |
| `home-switch [args]` | `home-manager switch --flake .`. |
| `deploy [args]` | `deploy-rs --skip-checks` (wrapper package in `devshell/default.nix`). |
| `deploy-multi <nodes...>` | Deploys several nodes in sequence. |
| `ssh-machine <name> [cmd]` | SSH to a system or home by name, resolving target/options from its deploy-rs node (see above). |
| `run-vm <host>` | Boots a system as a dev VM: installs `.keys/dev.key` into a temp `xchg/`, then `nix run`s `config.my.buildAs.devVM`. |
| `build-iso <host>` | Builds `config.my.buildAs.iso`. |
| `build-kexec <host>` | Builds `config.my.buildAs.kexecTree`. |
| `build-netboot <host>` | Builds `config.my.buildAs.netbootTree`. |
| `ragenix [args]` | `ragenix --identity .keys/dev.key` (see [Secrets](#secrets)). |
| `repl` | `nix repl .#`. |
| `fmt [args]` | `nixpkgs-fmt` (the canonical formatter). |
| `update-nixpkgs` | `nix flake update nixpkgs-{unstable,stable,mine,mine-stable}`. |
| `update-home-manager` | `nix flake update home-manager-{unstable,stable}`. |
| `update-installer` | Force-pushes the `installer` tag to trigger the installer release workflow. |
| `home-link` / `home-unlink` | Symlink (or remove) this `flake.nix` at `~/.config/home-manager/flake.nix` for standalone `home-manager` use. |
| `qemu-genmac` | Prints a random QEMU-suitable MAC (`52:54:00:xx:xx:xx`). |
| `ssh-get-ed25519 <host>` | Prints a host's ed25519 pubkey via `ssh-keyscan`. |
| `json2nix` | Converts JSON on stdin to formatted Nix. |

From [`devshell/install.nix`](../devshell/install.nix) (driven by `$INSTALLER`, the address of
a running custom installer, SSHing as root with `.keys/deploy.key`):

| Command | What it does |
|---|---|
| `installer-shell [cmd]` | Runs a command (default: a shell) inside the installer. |
| `do-install [--no-bootloader] [--no-substitute] <system>` | Builds the system's `toplevel`, `nix copy`s it into the installer's target store, sets the system profile, and activates it with `switch-to-configuration boot` (with `NIXOS_INSTALL_BOOTLOADER=1` unless `--no-bootloader`). |

From [`devshell/vm-tasks.nix`](../devshell/vm-tasks.nix) (remote VM consoles; they forward the
VM's unix sockets from `/run/vms/<vm>/` on `<host>` over SSH):

| Command | What it does |
|---|---|
| `vm-tty <host> <vm>` | Serial TTY of a VM in `minicom`. |
| `vm-monitor <host> <vm>` | QEMU monitor socket in `minicom`. |
| `vm-viewer <host> <vm>` | SPICE display in `virt-viewer` (not on Darwin). |

## Nix implementation

Every context uses **Determinate Nix** as its `nix.package`, for its performance features
(parallel evaluation and lazy trees) — not `determinate-nixd`; the daemon and `nix.conf` model
are unchanged, and the Determinate NixOS module is deliberately not imported.

- **Input and package.** The [`determinate-nix`](../flake.nix) input is the `nix-src` flake
  (`flakehub.com/f/DeterminateSystems/nix-src`), with `nixpkgs.follows = "nixpkgs-unstable"`. We
  build it ourselves against our pinned nixpkgs — FlakeHub's own cache needs authentication, so
  there is nothing to gain from leaving it unpinned — and it then flows through the Harmonia cache
  like everything else. `determinateOverlay` exposes it under the stable attr `determinate-nix`,
  added to both the devshell `pkgs'` and the config `configPkgs'` overlay lists, so systems, homes
  and the devshell all resolve the same package (`pkgs'.mine.determinate-nix`).
- **Settings.** `lib.my.c.nix.determinateSettings` (`lazy-trees`, `eval-cores = 0`) is merged into
  `nix.settings` for systems and homes and into the devshell's `nix.conf`. These keys are only
  understood by the Determinate binary.
- **Consumers follow automatically.** Everything that shells out to Nix references
  `config.nix.package` (deploy-rs, containers, `build`, netboot, Harmonia), so they inherit
  Determinate without further change.
- **`accept-flake-config`.** Set true only in the devshell `nix.conf`, `.envrc` (as
  `--accept-flake-config`, for direnv) and CI — the contexts that build this flake — so its
  `nixConfig` (the Harmonia cache) is trusted without an interactive prompt. It is deliberately not
  set system-wide: boxes already trust that cache via `nix.settings`, so a global setting would only
  blanket-trust every flake's `nixConfig` for no gain.

## Secrets

Secrets are age-encrypted files in [`secrets/`](../secrets), managed with **ragenix** (a fork
with a rekey flag, from the flake inputs).

### Per-box declarations

Each box declares `my.secrets.key`, the host public key its secrets encrypt to, and
`my.secrets.files.<name>`, whose values merge settings such as `owner` and `mode` into the agenix
secret. At runtime, identity paths come from the box's OpenSSH host keys. On tmproot boxes they are
read from the persistence directory because agenix runs before the persisted keys would otherwise
be available.

### Recipient rules

[`secrets.nix`](../secrets.nix) is generated from every system's `my.secrets.files` and `key`.
Each recipient list also includes `.keys/dev.pub`, so the development key can open every secret.
Run `ragenix -r` after adding a box or secret to re-key the files.

### Local keys and editing

The `ragenix` devshell command wraps `ragenix --identity .keys/dev.key`. The `.keys/` directory
contains that development key, the deploy key authorized for every box's `deploy` user, and other
keys referenced by `lib.my.c.sshKeyFiles`; it is required for editing secrets, deploying and running
development VMs.

## Dev VMs

Any system can be built as a throwaway QEMU VM via `config.my.buildAs.devVM` (the `build`
module extends the config with `qemu-vm.nix` and sets `my.build.isDevVM`). `run-vm <host>`
creates a temp dir, installs `.keys/dev.key` as `xchg/dev.key`, and runs the VM; inside, the
`secrets` module switches `age.identityPaths` to that dev key (`my.secrets.vmKeyPath`,
default `/tmp/xchg/dev.key`), so dev VMs can decrypt the boxes' secrets without the real host
keys. Dev VMs also get DHCP on `eth0`, an SSH port forward (host 2222 → guest 22), and are
automatically excluded from deploy targets.

## CI

GitHub/Gitea Actions workflows live in [`.gitea/workflows/`](../.gitea/workflows).

### `ci.yaml`

On pushes to `master`, this installs Determinate Nix on the runner (via
`DeterminateSystems/determinate-nix-action`, configured with the same performance settings and
Harmonia substituter as the boxes), runs `nix flake check --no-build`, then builds every attribute
of `.#ci.x86_64-linux`: systems as `system-<name>`, homes as `home-<name>` (with `@` changed to
`-at-`), packages as `package-<name>`, and the development `shell`. Each result is pushed to the
Harmonia cache with [`ci/push-to-cache.sh`](../ci/push-to-cache.sh).

It then builds `.#ciDrv.x86_64-linux`, a `linkFarm` of all CI attributes, and pushes it with
`UPDATE_PROFILE=1`. That updates the `nixfiles` profile on the cache box and collects old paths
according to the workflow's retention setting. The SSH store uses `/var/lib/harmonia`,
`HARMONIA_SSH_KEY`, and pinned `ci/known_hosts`; clients use `https://nix-cache.nul.ie` through
`lib.my.c.nix.cache`.

### `installer.yaml`

Pushing the `installer` tag (refreshed by `update-installer`) builds `my.buildAs.iso` and
`my.buildAs.netbootArchive`, then attaches both to a release.

### `update-docs.yaml`

On pushes to `master`, excluding its own commits, this runs the assignment, option and DNS
reference generators and commits changed outputs as `docs: Update generated references`.

### The docs generators

The generators are registered in [`pkgs/default.nix`](../pkgs/default.nix) as wrappers around
Python scripts under [`ci/`](../ci). They leave the worktree unchanged when their output is current;
the workflow stages `docs/` and uses `git diff --cached --quiet` to decide whether to commit.

`update-docs-assignments` ([`ci/update-docs-assignments.py`](../ci/update-docs-assignments.py))
evaluates `.#nixfiles.config.nixos.allAssignments` to JSON and rewrites the consolidated
[`Box assignments`](networking.md#box-assignments) tables in `docs/networking.md` — one table
per site (`colony` / `home` / `remote`), each between a `<!-- assignments: <site> -->` marker
and a closing `<!-- assignments-end -->` line. Boxes are grouped by site from their assignment
domain, and each `Box` cell links to that box's page when one exists. Hand-written text in the
**Notes** column is preserved across runs (keyed by box + assignment), so notes survive
regeneration. Individual box pages don't carry tables; they link to the consolidated section.

`update-docs-options` ([`ci/update-docs-options.py`](../ci/update-docs-options.py)) builds the
`nixos.optionsDoc` output (declared in [`nixos/default.nix`](../nixos/default.nix)) — a
`nixosOptionsDoc` JSON dump of the custom `my.*` options (declared with `mkOpt'` / `mkBoolOpt'` in
`nixos/modules/`). It's evaluated against a **minimal synthetic system**, since the shared modules
apply to every box, so defaults don't pick up a real host's values. The renderer writes
[`docs/reference/nixos-options.md`](reference/nixos-options.md), one table per module file. The
whole file is generated; edit the option descriptions in the modules, not the reference. The
internal `asX` build-target options are marked `internal = true` so they're excluded.

`update-docs-dns` ([`ci/update-docs-dns.py`](../ci/update-docs-dns.py)) accepts forward and reverse
zone names, discovers their authoritative nameservers through NS queries, and transfers each zone
over AXFR. If a private reverse zone is not visible through the configured recursive resolver, it
asks the authoritative servers discovered for the other requested zones. It updates only the
matching `<!-- dns: <zone> -->` blocks in the [`DNS records`](reference/dns.md) reference; the page's
headings and prose remain handwritten. Kea-managed owners are identified by `DHCID` records and
removed together with their A, AAAA and PTR records; SOA records and TTLs are also omitted.
