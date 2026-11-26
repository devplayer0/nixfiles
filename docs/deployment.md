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
- `deploy --targets .#<host1> .#<host2>` — deploys several nodes in one invocation.
  Pass shared options directly, e.g. `deploy --boot --targets .#river .#stream`.
- `deploy --boot .#<host>` — stages the config as the boot default **without** live-switching
  (deploy-rs's `--boot` maps to the custom activation's `boot` phase, which also does the
  generation cleanup). Use it when a live `switch` would cut the box off mid-change (e.g. a
  router WAN rework), then reboot to cut over.
- `nix flake check` includes deploy-rs's own `deployChecks` for the whole `deploy` attrset.

#### `ssh-machine`

`ssh-machine <name> [cmd]` connects using the deploy-rs node's SSH user and merged global and
node `sshOpts`. Box and home targets use the same `my.deploy.enable` gate and `@` → `-at-`
mangling as `deploy`. If a box sets `my.deploy.sshHostnames`, the command checks the
addresses in order for a reachable SSH port and uses the last address if the earlier checks fail.

For NixOS containers, use `ssh-machine middleman` or `ssh-machine shill.container-middleman`.
The qualified name selects the host when multiple containers share a name or a deploy node has
the same name. The command connects to the host's deploy node and uses `systemd-run` to open a
root Bash shell in the container or run the supplied command there. Stdin and the command's
exit status are available to the caller.

Connection settings and container names are cached together in `.cache/ssh-machine/`.
Normal connections read the cache without running Nix. A fingerprint of the checkout
automatically invalidates it. In a Jujutsu workspace (including secondary workspaces without a
Git checkout) it is the working-copy commit ID, so any snapshotted change counts, including new
files that are not ignored. In a Git-only checkout it is HEAD plus staged/unstaged tracked
changes; untracked files only count after `git add`. Ignored files never affect the fingerprint.
Any such edit, even an unrelated one, causes the next connection to refresh all nodes. Use `ssh-machine --refresh` to force a
refresh, or `ssh-machine --refresh <name> [cmd]` to refresh and connect. Refresh failures stop
the command; the previous cache is never used as a fallback.

Boxes default to `fish`, so pipe multi-statement remote scripts through `bash`, for example
`ssh-machine <name> bash -s < script.sh`. If a flaky agent stalls public-key authentication, use
`SSH_AUTH_SOCK= ssh-machine …`.

## Coding agents

The shared GUI home-manager module installs Codex and Claude Code from the `llm-agents` input,
retaining that input's tested nixpkgs pin. [CI proposes version updates](#llm-agents-updates).
To refresh the pin manually, run `nix flake update llm-agents`, then switch the system or home
configuration to use the updated packages.

The shared cache settings in `lib.my.c.nix.cache` and the flake's `nixConfig` include
the [Numtide binary cache](https://github.com/numtide/llm-agents.nix#binary-cache), so
both agents can be downloaded prebuilt. Keep the input's tested nixpkgs pin to preserve cache hits.

They also include the [nix-community cache](https://nix-community.org/cache/), which builds
unfree packages that `cache.nixos.org` doesn't, such as the MongoDB used by UniFi.

`programs.codex.mutableSettings` merges the declared status-line settings into the writable
`~/.codex/config.toml` during activation. Declared values take precedence on each switch;
other settings, including model selection, providers and project trust, remain imperative.

## Devshell commands

The repo ships a `numtide/devshell` ([`devshell/`](../devshell), entered via `direnv`). Run a
command with no arguments for its help. From
[`devshell/commands.nix`](../devshell/commands.nix):

| Command | What it does |
|---|---|
| `check-system <host> [nix args]` | Evaluates `.#nixosConfigurations."<host>".config.system.build.toplevel.drvPath` — catches module/option errors without building. Prefer this to validate a config change. |
| `build-system <host> [nix args]` | Builds the system's `toplevel` (extra args pass through to `nix build`). |
| `build-n-switch <args>` | `doas nixos-rebuild --accept-flake-config --flake .` (accepts the flake's cache settings and adds the repo as a git `safe.directory` for root first). |
| `build-home <name> [nix args]` | Builds `.#homeConfigurations."<name>".activationPackage`. |
| `home-switch [args]` | `home-manager switch --flake .`. |
| `deploy [args]` | `deploy-rs --skip-checks` (wrapper package in `devshell/default.nix`). |
| `deploy --targets .#<node1> .#<node2>` | Deploys several nodes in one invocation. |
| `ssh-machine <name> [cmd]` | Connect to a box, home-manager config or NixOS container using deploy-rs SSH settings. |
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
| `docs [file] [go-grip args]` | Previews Markdown in the browser with `go-grip` (default `docs/README.md`), rendered locally with live reload. |

From [`devshell/install.nix`](../devshell/install.nix) (driven by `$INSTALLER`, the address of
a running custom installer, SSHing as root with `.keys/deploy.key`):

| Command | What it does |
|---|---|
| `installer-shell [cmd]` | Runs a command (default: a shell) inside the installer. |
| `do-install [--no-bootloader] [--no-substitute] <system>` | Builds the system's `toplevel`, `nix copy`s it into the installer's target store, sets the system profile, and activates it with `switch-to-configuration boot` (with `NIXOS_INSTALL_BOOTLOADER=1` unless `--no-bootloader`). |

### VM consoles

The [`my.vms` module](../nixos/modules/vms.nix) provides `doas vm-tty <vm>` on the VM host.
It opens the serial console in `minicom` via `/run/vms/<vm>/tty.sock`.

The [devshell commands](../devshell/vm-tasks.nix) forward the VM's Unix sockets from
`/run/vms/<vm>/` on `<host>` over SSH.

| Command | What it does |
|---|---|
| `vm-tty <host> <vm>` | Serial TTY of a VM in `minicom`. |
| `vm-monitor <host> <vm>` | QEMU monitor socket in `minicom`. |
| `vm-viewer <host> <vm>` | SPICE display in `virt-viewer` (not on Darwin). |

## Version control

The shared [Home Manager module](../home-manager/modules/common.nix) enables `programs.git`
and `programs.jujutsu`, including Git LFS and `diff-so-fancy`, for graphical and non-graphical
homes. Jujutsu uses the identity declared in `programs.git.settings.user`; Home Manager writes
its `jj/config.toml`. The [devshell](../devshell/default.nix) also installs `jujutsu`, which
provides `jj`. Prefer `jj` when it is available and the checkout has a Jujutsu workspace;
use Git for Git-only checkouts and Git-specific tooling such as the installer-tag command
and CI scripts.

To use an existing Git checkout with both tools, run `jj git init --colocate` at its root.
This creates local `.jj` metadata and keeps `.git` for Nix flake source discovery and existing
Git tooling. Switch the home configuration to install the managed identity. When using only
the devshell, configure your identity with `jj config set --user user.name '<name>'` and
`jj config set --user user.email '<email>'` before creating commits.

| Task | Command |
|---|---|
| Inspect the working copy and history | `jj status`, `jj diff`, `jj log` |
| Describe the current change | `jj describe -m 'area/scope: Capitalized summary'` |
| Start the next change | `jj new` |
| Inspect a completed description | `jj log --no-graph -r <revision> -T description` |
| Fetch remote history | `jj git fetch` |
| Name a revision for publishing | `jj bookmark create <name> -r <revision>` |
| Move an existing bookmark | `jj bookmark set <name> -r <revision>` |
| Publish a bookmark | `jj git push --bookmark <name>` |

`@` is the working-copy revision; after `jj new`, the completed change is normally `@-`.
Working-copy edits are snapshotted automatically, without a staging step. Inspect existing
changes before editing, keep unrelated work separate, and check the target revision before
rewriting history or moving a bookmark. Follow the commit-message conventions in
[`AGENTS.md`](../AGENTS.md#conventions).

See the upstream [Jujutsu CLI reference](https://docs.jj-vcs.dev/latest/cli-reference/)
for command options and [Git compatibility](https://docs.jj-vcs.dev/latest/git-compatibility/)
for colocation details.

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
  `nixConfig` (the Harmonia and Numtide caches) is trusted without an interactive prompt. It is
  deliberately not set system-wide: boxes already trust those caches via `nix.settings`, so a global setting would only
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
Each recipient list also includes `.keys/dev.pub`, so the development key can open every secret,
and `.keys/slop-broker.pub`, so [`slop-broker`](slop-broker.md#secrets) can change secrets for
agents.
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

## OpenWrt images

The OpenWrt boxes are not NixOS and are not deployed by this flake, but their firmware is built
here. [`openwrt/default.nix`](../openwrt/default.nix) declares one image per box and packages it
through [`astro/nix-openwrt-imagebuilder`](https://github.com/astro/nix-openwrt-imagebuilder),
which drives OpenWrt's official ImageBuilder — prebuilt target packages assembled into a sysupgrade
image, with no cross-toolchain involved.

| Output | Box | Release |
|---|---|---|
| `openwrt-fergal` | [fergal](sites/colony/fergal.md) | `snapshot` |
| `openwrt-fergal-release` | The same, on the release branch | pinned in `openwrt/default.nix` |

Both are in `ci`, so images are built and pushed to the Harmonia cache like everything else. Build
one with `nix build .#openwrt-fergal`; the result holds the `-squashfs-sysupgrade.bin` to flash,
plus a package manifest and an SBOM. Getting it onto the box is a guided procedure of its own —
see [`openwrt-flash.md`](openwrt-flash.md).

Packages are baked into the image rather than installed on the box. OpenWrt's package server keeps
only the current build of each feed, so a box that installs packages at runtime stops being able to
do so as soon as the feed moves on from the firmware it is running. Adding a package means editing
the image's `packages` list and reflashing.

### The feed pin

OpenWrt's download server is never at rest: snapshot is rebuilt daily, and
`releases/<version>/packages/` is a symlink to the rolling `packages-<major>` feed shared by every
point release. Building straight against it fails on hash mismatches and, worse, resolves the
package list by import-from-derivation — which would drag *evaluation* of this flake onto the
network and let an OpenWrt feed rebuild break `check-system` for unrelated boxes.

The `openwrt-feeds` input exists to stop that. It holds expanded per-package metadata and vendors
the repository indexes themselves, so every `.apk` is a plain pinned `fetchurl`, image builds read
the indexes from the flake rather than OpenWrt's mutable URLs, and no import-from-derivation is
involved. Its generated files run to hundreds of thousands of lines and are rewritten wholesale on
each refresh, which is why they live in their own repository rather than here. Regenerate and push
that repository with `nix run .#update`, then refresh this flake's pin with
`nix flake update openwrt-feeds`; adding a release or target means adding it to that repository's
`pins` first.

## CI

GitHub/Gitea Actions workflows live in [`.gitea/workflows/`](../.gitea/workflows).

### `ci.yaml`

On pushes to `master`, this installs Determinate Nix on the runner (via
`DeterminateSystems/determinate-nix-action`, configured with the same performance settings and
Harmonia substituter as the boxes). A newer push cancels a run still in progress. CI normally
runs `nix flake check --no-build` first and keeps import from derivation disabled. It then runs
[`ci/build-and-cache.py`](../ci/build-and-cache.py), which builds every attribute of
`.#ci.x86_64-linux`: systems as `system-<name>`, homes as `home-<name>` (with `@` changed to
`-at-`), packages as `package-<name>`, and the development `shell`.

The script works in stages:

- **Collect garbage.** It deletes cache-profile generations older than their retention period,
  then collects unreachable paths so a full cache cannot prevent collection from being reached.
  Paths pushed by `slop build` survive collection through their own GC roots (see
  [`slop-broker.md`](slop-broker.md#binary-cache)).
- **Evaluate.** [`nix-eval-jobs`](https://github.com/nix-community/nix-eval-jobs) evaluates the
  attributes in a pool of workers. Each worker reuses one evaluation of the flake for several
  jobs, and the worker count and per-worker memory bound (`CI_EVAL_WORKERS`,
  `CI_EVAL_WORKER_MEMORY`) cap the evaluation's memory on the runner.
- **Build.** One `nix build --keep-going` builds every evaluated derivation, so a failing job
  doesn't stop the others.
- **Cache.** Every output that built is pushed to the Harmonia cache with
  [`ci/push-to-cache.sh`](../ci/push-to-cache.sh). Any evaluation or build failure fails the run
  at this point.
- **Update the profile.** A `linkFarm` of all the outputs, built from their known store paths
  rather than a second evaluation, is pushed with `UPDATE_PROFILE=1`. That updates the
  `nixfiles` profile on the cache box.

When `.#ciIfdReasons.x86_64-linux` lists an active exception, CI logs a warning with the reason
and allows import from derivation for the evaluation. The evaluation workers then wait on those
builds in parallel. CI runs a build-capable flake check after caching and before updating the
profile. CI checks [the shared runtime replacement list](../lib/runtime-dependency-replacements.nix)
against the nixpkgs channels used by its systems and standalone homes. A matching entry
requires reading generated store reference graphs during evaluation.

The SSH store uses `/var/lib/harmonia`, `HARMONIA_SSH_KEY`, and pinned `ci/known_hosts`; clients
use `https://nix-cache.nul.ie` through `lib.my.c.nix.cache`.

### `installer.yaml`

Pushing the `installer` tag (refreshed by `update-installer`) builds `my.buildAs.iso` and
`my.buildAs.netbootArchive`, then attaches both to a release.

### llm-agents updates

[`update-llm-agents.yaml`](../.gitea/workflows/update-llm-agents.yaml) checks for updates every
four hours and can also be run manually on `master`. It matches packages directly installed
by the x86_64 Linux NixOS and home-manager configurations to derivations exported by
`llm-agents`. This discovers the tracked packages without building a whole system.

When an installed version changes, CI commits the updated lockfile on the dedicated
`automation/llm-agents` branch. The PR description tabulates the version changes and links
the upstream comparison, and the commit message lists them too. New versions refresh the branch
behind the existing open PR, and the updater rewrites the description to match. Upstream revisions with the same package
versions leave that branch alone.

- **Declining:** close the PR without merging. CI won't propose the same versions again, and
  opens a new PR once a later version appears.
- **Obsolete PRs:** if `master` already has the latest installed versions, for example after a
  manual update, CI comments on the open PR and closes it.

[`llm-agents.yaml`](../.gitea/workflows/llm-agents.yaml) builds the discovered packages for
the update commit using the flake's caches. The updater dispatches the build explicitly
because Gitea suppresses automatic workflow events from its job token. The updater needs
the repository's Actions token limits to allow writes to code, pull requests and Actions.

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
