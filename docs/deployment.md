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
- Generated profiles:
  - **`system`** — activates `config.system.build.toplevel` with
    `switch-to-configuration switch`, with workarounds for the `/tmp` cwd issue
    (NixOS/nixpkgs#73404) and the systemd-boot `loader.conf` default-entry issue
    (deploy-rs#31), then prunes old generations (`nix-env --delete-generations +10`,
    tunable via `keepGenerations`, 0 disables).
  - **`container-<name>`** — one per `my.containers.instances` entry, activating the
    container's `my.buildAs.container` toplevel into
    `/nix/var/nix/profiles/per-container/<name>/system`. With `hotReload` (default) the
    profile *reloads* `systemd-nspawn@<name>` (restarting only if the container is down or
    still running the placeholder "dummy" init); otherwise it restarts it. Generation cleanup
    applies here too.
  - Profiles deploy in order `system`, then the containers.

### Usage

- `deploy .#<host>` — the devshell's `deploy` is a wrapper that adds `--skip-checks`. Node
  names are the system names (`deploy .#git`).
- `deploy-multi <hosts...>` — loops `deploy` over several nodes (extra args via `$O`).
- `deploy --boot .#<host>` — stages the config as the boot default **without** live-switching
  (deploy-rs's `--boot` maps to the custom activation's `boot` phase, which also does the
  generation cleanup). Use it when a live `switch` would cut the box off mid-change (e.g. a
  router WAN rework), then reboot to cut over.
- `ssh-machine <name> [cmd]` — resolves `user@host` and the merged global+node `sshOpts` from
  `.#deploy` (same `my.deploy.enable` gate as `deploy`, same `@` → `-at-` mangling), then
  execs `ssh`. Boxes default to the `fish` login shell; pipe multi-statement remote scripts
  through `bash` (`ssh-machine <name> bash -s < script.sh`). If outbound SSH hangs at the
  publickey step (flaky agent), use `SSH_AUTH_SOCK= ssh-machine …`.
- `nix flake check` includes deploy-rs's own `deployChecks` for the whole `deploy` attrset.

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

## Secrets

Secrets are age-encrypted files in [`secrets/`](../secrets), managed with **ragenix** (a fork
with a rekey flag, from the flake inputs).

- Each box declares `my.secrets.key` (the host public key its secrets encrypt to) and
  `my.secrets.files.<name>` (files to decrypt; attribute values merge into the agenix secret,
  e.g. `owner`/`mode`). At runtime the `secrets` module decrypts via
  `age.secrets."<name>".path`, with identity paths derived from the box's OpenSSH host keys —
  read from the tmproot persistence dir when there is one, since agenix runs before persisted
  keys would otherwise be available.
- [`secrets.nix`](../secrets.nix) (the ragenix rules file at the repo root) is **generated**:
  it evaluates the flake, collects every system's `my.secrets.files` + `key`, and emits each
  secret with its recipient list — always including `.keys/dev.pub` so the dev key can open
  everything. Re-running `ragenix -r` re-keys after adding a box or secret.
- The `ragenix` devshell command wraps `ragenix --identity .keys/dev.key`; use it to
  edit/rekey secrets.
- The `.keys/` directory holds the dev key (`dev.key`/`dev.pub`), the deploy key
  (`deploy.key`/`deploy.pub`, authorized on every box's `deploy` user), and assorted other
  keys referenced by `lib.my.c.sshKeyFiles`. It is required for editing secrets, deploying,
  and running dev VMs.

## Dev VMs

Any system can be built as a throwaway QEMU VM via `config.my.buildAs.devVM` (the `build`
module extends the config with `qemu-vm.nix` and sets `my.build.isDevVM`). `run-vm <host>`
creates a temp dir, installs `.keys/dev.key` as `xchg/dev.key`, and runs the VM; inside, the
`secrets` module switches `age.identityPaths` to that dev key (`my.secrets.vmKeyPath`,
default `/tmp/xchg/dev.key`), so dev VMs can decrypt the boxes' secrets without the real host
keys. Dev VMs also get DHCP on `eth0`, an SSH port forward (host 2222 → guest 22), and are
automatically excluded from deploy targets.

## CI

GitHub/Gitea Actions workflows live in [`.gitea/workflows/`](../.gitea/workflows):

- **`ci.yaml`** (push to `master`): `nix flake check --no-build`, then for every attribute of
  `.#ci.x86_64-linux` (each system as `system-<name>`, each home as `home-<name>` with `@` →
  `-at-`, each package as `package-<name>`, plus the dev `shell`) it builds and pushes the
  result to the Harmonia binary cache with [`ci/push-to-cache.sh`](../ci/push-to-cache.sh).
  Finally it builds `.#ciDrv.x86_64-linux` (a `linkFarm` of all CI attrs) and pushes it with
  `UPDATE_PROFILE=1`, which updates the `nixfiles` profile on the cache box and garbage
  collects paths older than 60 days. The cache is `ssh-ng://harmonia@object-ctr.ams1.int.nul.ie`
  (remote store `/var/lib/harmonia`), keyed by the `HARMONIA_SSH_KEY` secret with a pinned
  `ci/known_hosts`; clients consume it as `https://nix-cache.nul.ie` (see `lib.my.c.nix.cache`).
- **`installer.yaml`** (push of the `installer` tag; `update-installer` refreshes it): builds
  the installer's `my.buildAs.iso` and `my.buildAs.netbootArchive` and attaches both to a
  release.
- **`update-docs.yaml`** (push to the docs branch, skipping its own commits): runs
  `nix run .#update-docs-assignments` and commits any changes as
  `docs: update assignment tables`.

### The docs assignment-table updater

`update-docs-assignments` is registered in [`pkgs/default.nix`](../pkgs/default.nix) (a
`writeShellScriptBin` wrapping [`ci/update-docs-assignments.py`](../ci/update-docs-assignments.py)).
It evaluates `.#nixfiles.config.nixos.allAssignments` to JSON, walks `docs/**/*.md`, and for
each file looks for a marker line `<!-- assignments: <box> -->` where `<box>` is the **file's
own stem** (e.g. `river.md` → `river`) and names a real box. The generated table (columns
`Name | Assignment | IPv4 | IPv6 | Domain | Notes`) is (re)written between the marker and a
closing `<!-- assignments-end -->` line, with an `<!-- assignments-start -->` line inserted
after the marker on the first run. Hand-written text in the **Notes** column is preserved
across runs (keyed by the Assignment cell), so notes survive regeneration. Pages that want a
table only need the marker + end marker; pages without markers (including the three top-level
docs) are left alone. The script exits non-zero when it changed something, which is how the
workflow knows whether to commit.
