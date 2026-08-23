# Architecture

This flake does **not** use the stock pattern of calling `nixosSystem` once per host in
[`flake.nix`](../flake.nix). Instead it runs a single `lib.evalModules` evaluation over its own
module tree, producing one big top-level config (`self.nixfiles`) from which the real flake
outputs (`nixosConfigurations`, `homeConfigurations`, `nixosModules`, `deploy`, …) are derived.
Per-host files declare *options* (`nixos.systems.<name>`); the machinery in
[`nixos/default.nix`](../nixos/default.nix) and
[`home-manager/default.nix`](../home-manager/default.nix) turns those into evaluated NixOS /
home-manager configurations.

## The top-level evaluation

`flake.nix`'s `outputs` builds a `nixfiles` attrset via `evalModules` over:

- An inline module that seeds `_module.args` (`lib`, `pkgsFlakes`, `hmFlakes`, `self`, `inputs`,
  `pkgs'`), sets `nixos.secretsPath = ./secrets`, and sets the global deploy-rs SSH option
  `deploy-rs.deploy.sshOpts = [ "-i" ".keys/deploy.key" ]`.
- `nixos/modules/misc/assertions.nix` from the unstable nixpkgs (so the top-level evaluation has
  the standard `assertions` / `warnings` options).
- [`nixos/`](../nixos/default.nix) — defines `nixos.*` options (`systems`, `modules`,
  `allAssignments`, `vpns`, `secretsPath`) and `mkSystem`.
- [`home-manager/`](../home-manager/default.nix) — defines `home-manager.*` options (`homes`,
  `modules`) and `mkHome`.
- [`deploy-rs.nix`](../deploy-rs.nix) — defines `deploy-rs.*` and renders the deploy config.
- Every file in the `configs` list — the boxes themselves
  ([`nixos/boxes/`](../nixos/boxes) plus [`nixos/installer.nix`](../nixos/installer.nix); the
  home-manager entries are currently commented out, see [Home-manager](#home-manager)).

The resulting `nixfiles.config` is mapped onto flake outputs:

| Top-level option (`nixfiles.config`) | Flake output |
|---|---|
| `nixos.systems.<name>.rendered` | `nixosConfigurations.<name>` |
| `home-manager.homes.<name>.configuration` | `homeConfigurations.<name>` |
| `nixos.modules` | `nixosModules` |
| `home-manager.modules` | `homeModules` |
| `deploy-rs.rendered` | `deploy` |

`nixfiles` itself is also a flake output, so anything in the top-level config can be addressed
directly — e.g. `build-iso` builds
`.#nixfiles.config.nixos.systems."<host>".configuration.config.my.buildAs.iso`. The flake also
exposes `lib` (the extended unstable nixpkgs lib, including `lib.my`), `inputs`, `nixpkgs`
(the `pkgs'` channel sets), and `overlays.default` (the custom packages from
[`pkgs/`](../pkgs/default.nix)).

Per platform (`eachDefaultSystem`), the flake produces:

- `packages` — everything from `pkgs/`, flattened.
- `checks` — every `homeConfigurations.*.activationPackage` plus deploy-rs's own `deployChecks`.
- `devShells.default` — the `numtide/devshell` from [`devshell/`](../devshell) (see
  [deployment.md](deployment.md)).
- `ci.<system>` — one attr per buildable thing (`system-<name>`, `home-<name>` with `@` mangled
  to `-at-`, `package-<name>`, plus `shell`), consumed by CI; `ciDrv` is a `linkFarm` of all of
  them.

## Systems: `systemOpts` and `mkSystem`

Each entry of `nixos.systems` is a submodule defined by `systemOpts` in
[`nixos/default.nix`](../nixos/default.nix):

| Option | Type / default | Meaning |
|---|---|---|
| `system` | enum of `defaultSystems` | Nix platform string, e.g. `"x86_64-linux"`. |
| `nixpkgs` | one of `unstable`/`stable`/`mine`/`mine-stable`, default `"unstable"` | nixpkgs channel for the system. |
| `home-manager` | same enum, defaults to `nixpkgs` | home-manager channel. |
| `hmNixpkgs` | same enum, defaults to `nixpkgs` | nixpkgs channel used for home-manager's own pkgs when it doesn't share the system's. |
| `docCustom` | bool, default `false` | Include nixfiles' custom modules in the generated NixOS manual (slow). |
| `assignments` | attrsOf `assignmentOpts` | The box's network assignments (see [networking.md](networking.md)). |
| `extraAssignments` | attrsOf attrsOf `assignmentOpts` | Extra assignments for things not on the box itself (e.g. the routers' floating VIP entries). |
| `configuration` | custom merged type | The actual NixOS configuration module(s); merging runs `mkSystem`. |
| `rendered` | unspecified, default `configuration` | What ends up in `nixosConfigurations.<name>` — overridden for boxes built as something other than a plain system (e.g. `installer` renders `config.my.asISO`, containers render `config.my.asContainer`). |

`mkSystem` does the real work:

1. It selects the channel's nixpkgs flake (`pkgsFlakes.${config'.nixpkgs}`).
   - It imports `nixos/lib/eval-config.nix` **by hand** because the flake force-sets `lib`;
     otherwise `eval-config.nix` would import its own unextended copy.
   - The supplied library is the channel's `pkgs.lib` extended with `lib.my` and a
     `versionOverlay` that stamps `system.nixos` with the flake revision and channel.
2. `specialArgs` gives every module access to `self`, `inputs`, `pkgsFlakes`, the box's own
   `pkgsFlake`, `allAssignments` (every box's assignments), and `systems` (all of
   `nixos.systems`). Passing these via `specialArgs` (rather than module `imports`) avoids
   infinite recursion.
3. The module list is: the home-manager channel's `nixosModules.default`, every module in
   `nixos.modules` (the shared modules, see below), an inline module, and the box's own
   `configuration` definitions (wrapped with `inlineModule'` so error messages keep file
   provenance).
4. The inline module wires the plumbing:
   - `_module.args`: `secretsPath`, `vpns` (the flake-level `nixos.vpns`), the box's own
     `assignments`, and `pkgs'` — an attrset of **all four nixpkgs channels** for this box's
     platform, so a module can grab a package from another channel (e.g. `pkgs'.stable.foo`).
   - `system.name` is the attribute name of the box.
   - `networking.hostName` / `networking.domain` default from the `internal` assignment (see
     [networking.md](networking.md)).
   - `nixpkgs.system` is set and the overlays computed at flake level (lib overlay + custom
     packages) are passed through, so `pkgs` is imported modularly with config and overlays
     applied.
   - `home-manager.useGlobalPkgs` defaults to true when the system and home-manager channels
     match; a warning is emitted when they deliberately differ.
   - `home-manager.sharedModules` includes every module in `home-manager.modules` plus an inline
     module. The inline module passes `pkgsPath` / `pkgs'`, disables the release check, and pins
     `home.stateVersion` through `homeStateVersion` (`22.11` for stable-flavoured channels,
     `23.05` otherwise).
5. Finally `applyAssertions` throws with all failed assertion messages (and shows warnings)
   when the merged configuration is forced.

## The four nixpkgs channels

`flake.nix` builds `pkgsFlakes` (nixpkgs) and `hmFlakes` (home-manager):

| Channel | nixpkgs input | home-manager input |
|---|---|---|
| `unstable` | `nixpkgs/nixos-unstable` | `home-manager` (master) |
| `stable` | `nixpkgs/nixos-26.05` | `home-manager/release-26.05` |
| `mine` | `github:devplayer0/nixpkgs/devplayer0` (personal fork) | alias of `unstable` (no fork exists) |
| `mine-stable` | `github:devplayer0/nixpkgs/devplayer0-stable` | alias of `stable` |

Each channel's `lib` is extended with the `libOverlay` (`lib.my` + flake-utils). Two package
sets are built per channel:

- `pkgs'` — with the devshell/ragenix/deploy-rs/home-manager overlays; used for the dev shell
  and `packages`, and exposed as the flake's `nixpkgs` output.
- `configPkgs'` — with just the lib + custom-packages overlays and an `allowUnfreePredicate`
  (Widevine / Chromium); this is the `pkgs'` threaded into the top-level evaluation, from
  which each box's `pkgs` and per-channel `pkgs'` module args (and home-manager's base
  `pkgs`) are taken.

A box picks its channel with `nixpkgs = "mine"` (most boxes), `"mine-stable"` (e.g. `colony`),
etc. Inside a module, `pkgs` is the selected channel and `pkgs'` is the attrset of all four
(`pkgs'.<channel>.<attr>`).

## `lib.my` and the `my.*` namespace

[`lib/default.nix`](../lib/default.nix) extends nixpkgs `lib` with a `my` attrset. The
flake-level `lib` (`pkgsFlakes.unstable.lib` so extended) is for platform-independent flake
use only; each box gets its own channel's lib extended the same way. Contents:

- **Option helpers** — `mkOpt'`, `mkBoolOpt'`, `nullOrOpt'`, `mkDefault'` (slightly stronger than
  `mkDefault`), `mkVMOverride'`, `inlineModule'` / `inlineModule`
  (attach `_file` provenance), `commonOpts` (the shared `system`/`nixpkgs`/`home-manager`
  options and the `moduleType` used for exported modules), `applyAssertions`, `duplicates`.
- **`lib.my.net`** — CIDR/IP math (`net.cidr.host`, `net.cidr.subnet`, `net.types.ipv4`, …)
  from the `libnetRepo` input (`oddlama/nixos-extra-modules`' `netu.nix`). Used for nearly all
  address arithmetic; addresses are almost never written literally.
- **`lib.my.c`** — shared constants from [`lib/constants.nix`](../lib/constants.nix): static
  UID/GID assignments, kernel package selection (`kernel.lts`/`kernel.latest`), nginx config
  snippets, networkd snippets (`networkd.noL3`), the binary-cache settings (`nix.cache`),
  and the per-site domains/prefixes/VIPs described in [networking.md](networking.md).
- **`lib.my.dns`** — zone-generation helpers from [`lib/dns.nix`](../lib/dns.nix): `fwdRecords`
  / `ptrRecords` / `ptr6Records` rendered from `allAssignments`, plus the LUA-record helpers
  (`ifaceA`, `lookupIP`) used by the home routers.
- **networkd helpers** — `networkdAssignment` (assignment → `systemd.network` network, see
  [networking.md](networking.md)), `mkVLAN`, `dockerNetAssignment`.

### Misc

The remaining helpers are `mkDefaultSystemsPkgs`, `flakePackageOverlay` (wrap another flake's
package as an overlay), `isIPv6` / `parseIPPort` / `netBroadcast`, `nft` chain-name helpers,
`systemdAwaitPostgres`, `vm.*` LVM disk descriptors for the `vms` module, the typed `deploy-rs`
option definitions (`lib.my.deploy-rs`), `netbootKeaClientClasses` (iPXE/EFI DHCP client classes),
and `homeStateVersion`.

Custom NixOS / home-manager modules declare their options under the `my.*` namespace (the root
`options.my` is declared in `nixos/modules/common.nix` / `home-manager/modules/common.nix`) —
e.g. `my.secrets`, `my.build`, `my.tmproot`, `my.firewall`, `my.server`, `my.deploy`,
`my.vms`, `my.containers`.

## Shared modules

Registered in [`nixos/modules/_list.nix`](../nixos/modules/_list.nix) and applied to **every**
system (box files opt in per-feature via `my.*` options). The table below is the overview — what
each module is *for*; for the exhaustive, CI-generated per-option reference (types, defaults,
descriptions) see [`reference/nixos-options.md`](reference/nixos-options.md).

| Module | Provides |
|---|---|
| `common` | Baseline for all boxes: imports the impermanence, ragenix (age), copyparty and harmonia NixOS modules; pins `system.stateVersion`; `doas` instead of `sudo`; immutable users; nix settings (flakes, `ca-derivations`, the `nix-cache.nul.ie` substituter); declares the `my` option root. |
| `user` | `my.user` — the primary user: `users.users` + matching `home-manager.users` entry, wheel/doas, SSH authorized key from `.keys/me.pub`, shell taken from the home config, home persistence under tmproot. |
| `build` | `my.build` — alternate build targets via `extendModules`: `my.buildAs.devVM` (QEMU dev VM), `iso`, `container`, `kexecTree`, `netbootTree`/`netbootArchive`; `my.build.isDevVM` marker; `allHardware` profile toggle. |
| `dynamic-motd` | `my.dynamic-motd` — runs a script via `pam_exec` to generate the MOTD on login/ssh. |
| `tmproot` | `my.tmproot` — tmpfs `/` plus impermanence persistence (`persistence.dir`), with a `tmproot-unsaved` helper that walks the root tmpfs and lists files not covered by persistence. |
| `firewall` | `my.firewall` — nftables firewall: `tcp.allowed`/`udp.allowed` port lists, `trustedInterfaces`, NAT with `forwardPorts`, `extraRules` escape hatch; sane ICMP/ICMPv6/PMTUD rules baked in. |
| `server` | `my.server.enable` — server commonalities: getty autologin, LLMNR off, tightened fstrim timers, GUI and NixOS documentation off. |
| `deploy-rs` | `my.deploy` — per-box deploy-rs node/profile generation and the `deploy` user; see [deployment.md](deployment.md). |
| `secrets` | `my.secrets` — ragenix/agenix wiring: `files` to decrypt from `secrets/`, host `key` to encrypt for, identity paths derived from the OpenSSH host keys (persistence-aware), dev-key identity inside dev VMs. |
| `containers` | `my.containers.instances` — `systemd-nspawn` NixOS containers whose systems come from `nixos.systems` rendered `asContainer`, with bridge/macvlan networking, bind mounts, `hotReload` (reload instead of reboot) and a placeholder "dummy" init before first deploy. |
| `vms` | `my.vms.instances` — QEMU/KVM VMs as systemd units: TAP/bridge networking, LVM-backed disks, VFIO host-device passthrough (with udev tagging), UEFI, SPICE/TTY/QMP unix sockets under `/run/vms/`, clean shutdown via QMP `system_powerdown`. |
| `network` | Baseline networking: networkd only (`useDHCP = false`), IPv6 on, resolved domain/negative-cache settings; dev VMs get DHCP on `eth0` and an SSH port forward. |
| `pdns` | `my.pdns` — PowerDNS: authoritative server driven by BIND-style zone files (with templating and serial management) and recursor extra-settings wiring. |
| `nginx-sso` | `my.nginx-sso` — runs `nginx-sso` (instead of the stock NixOS module) and generates per-instance nginx `auth_request` include files. |
| `gui` | `my.gui.enable` (default on) — desktop baseline: graphics, polkit, swaylock PAM entry, Android udev rules, screenshot tmpdir. |
| `l2mesh` | Consumes `nixos.vpns.l2` — builds the VXLAN + IPsec layer-2 meshes between edge routers; see [networking.md](networking.md). |
| `borgthin` | `my.borgthin.jobs` — borg backups of thin-LVM snapshots to local or SSH repos on a systemd timer, with pruning. |
| `nvme` | `my.nvme` — sets the NVMe host NQN/hostid and, optionally, NVMe-oF-over-RDMA boot in the initrd. |
| `spdk` | `my.spdk` — SPDK target configuration (JSON RPC-driven) plus `spdk-rpc`/`spdk-setup`/`spdk-debug` helper tools. |
| `librespeed` | `my.librespeed` — a LibreSpeed speedtest: generated frontend (from the `librespeed-go` package in `pkgs/`) plus backend settings. |
| `netboot` | `my.netboot` — iPXE netboot server (TFTP/HTTP, menu) and the client-side loader that installs boot entries. |

Home-manager modules, registered in
[`home-manager/modules/_list.nix`](../home-manager/modules/_list.nix) and applied to every
home (including the per-user homes attached to systems via `my.user.homeConfig`):

| Module | Provides |
|---|---|
| `common` | Home baseline: `my.shell`, `my.ssh.authKeys`, `my.isStandalone` (home-manager running standalone vs inside NixOS), fish setup and completions generation, common programs. |
| `gui` | `my.gui` — the sway-based desktop: waybar, notifications, lock/saver plumbing (including the "doomsaver"), terminal and fonts. |
| `deploy-rs` | `my.deploy` for standalone homes — generates a `home` profile (home-manager activation) and deploy node; auto-disabled for NixOS-attached homes. |
| `swaync` | `my.swaync` — typed configuration module for Sway Notification Center. |

## Adding a box

1. Create a file (or directory with a `default.nix`) under [`nixos/boxes/`](../nixos/boxes)
   that sets `nixos.systems.<name> = { system = "x86_64-linux"; nixpkgs = "mine"; assignments =
   { … }; configuration = { … }: { … }; };`. Nested boxes (VMs, containers) live under their
   host's directory (e.g. `nixos/boxes/colony/vms/estuary/`).
2. Add the path to the `configs` list in [`flake.nix`](../flake.nix).
3. Give the box an `internal` assignment (name/domain) if it gets one — `hostName`/`domain`
   default from it — and declare `my.secrets.key` if it has secrets.
4. Evaluate it with `check-system <name>` (cheap) before `build-system <name>`.

## Adding a shared module

1. Drop the file in [`nixos/modules/`](../nixos/modules) (or
   [`home-manager/modules/`](../home-manager/modules)) with options under `my.*`, declared via
   the `lib.my` helpers (`mkOpt'`, `mkBoolOpt'`).
2. Register it in the corresponding `_list.nix` (name → path). It is then applied to every
   box and exported as `nixosModules.<name>` / `homeModules.<name>`.

## Home-manager

Home-manager follows the same option-definition and evaluation split as NixOS.

### `homeOpts`

[`home-manager/default.nix`](../home-manager/default.nix) defines each entry with these options:

| Option | Meaning |
|---|---|
| `system` | Target platform. |
| `nixpkgs` | nixpkgs channel used for the home packages. |
| `home-manager` | home-manager channel. |
| `homeDirectory` / `username` | User identity and home path. |
| `configuration` | The home-manager module definitions evaluated by `mkHome`. |

### `mkHome`

1. Calls the selected channel's `lib.homeManagerConfiguration`.
2. Supplies that channel's `pkgs'` with `config` emptied, allowing home-manager to apply package
   configuration and overlays through its module system.
3. Passes `inputs`, `pkgsFlakes` and the selected `pkgsFlake` through `extraSpecialArgs`.
4. Loads every module in `home-manager.modules` plus an inline module that sets
   `home.homeDirectory` / `home.username` and exposes every channel through the `pkgs'` module
   argument.
5. Pins `home.stateVersion` through `homeStateVersion`.

### Standalone homes

Standalone homes live in [`home-manager/configs/`](../home-manager/configs) and are named
`<user>@<host>` (deploy-rs mangles the `@` to `-at-`). `macsimum` is a home-manager-only
config — an `x86_64-darwin` macOS box with no NixOS side.

No standalone homes are currently wired into the flake: `home-manager/configs/macsimum.nix` is
commented out of `configs`, while `home-manager/configs/castle.nix` is not listed. Consequently,
`nixfiles.config.home-manager.homes` evaluates to `{}`. Most user configuration instead accompanies
NixOS boxes through `my.user.homeConfig`.
