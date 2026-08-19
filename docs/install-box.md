# Installing a box

Procedure for bringing a new NixOS box into this flake, from bare hardware booted into the custom
installer through to a deployable system. Written to be followed by a person or any coding agent; a
Claude Code entry point exists at `.claude/skills/install-box/` but the steps below are the
canonical source.

The install is **guided, not automated**: the mechanical steps (probing hardware, partitioning,
writing the config, evaluating it) can be done straight through, but stop at the judgment points
(marked ⏸) — what the box actually is, wiping disks, and running `do-install` itself. Keep a running
summary and present it before any destructive step.

For the installer image itself — what it contains, how it is built and released — see
[`misc/installer.md`](misc/installer.md).

## Setup facts

- **Installer access:** the box boots the custom installer (ISO, kexec or netboot) and is reached
  over SSH as `root` with `.keys/deploy.key`. The devshell sets
  `INSTALLER_SSH_OPTS = "-i .keys/deploy.key"`; set `INSTALLER` to the address, and
  `INSTALLER_SSH_PORT` if it is not 22.
- **Devshell commands** (from [`devshell/install.nix`](../devshell/install.nix)):
  `installer-shell [cmd]` and `do-install [--no-bootloader] [--no-substitute] <system>`.
- **`INSTALL_ROOT`** is `/mnt` in the installer's environment — everything is mounted under it and
  `do-install` reads it from the installer rather than assuming.
- **`show-hw-config`** is a shell *alias* in the installer (wrapping
  `nixos-generate-config --show-hardware-config --root $INSTALL_ROOT`), so it needs an interactive
  shell: `installer-shell bash -lic show-hw-config`. A plain `installer-shell show-hw-config` will
  not find it.
- **Validation:** `check-system <host>` evaluates a system without building it — use it while
  iterating. Only `build-system` when you need the artifact.
- Nix reads the flake through git, so **`git add` new files before evaluating** — an untracked
  box directory fails with "Path … is not tracked by Git", not a Nix error.

## Phase 1 — Establish what the box is

⏸ Settle these before writing anything; they decide where every file goes and they are not
recoverable from the hardware:

1. **Name and site** — the box name doubles as the `nixos.systems.<name>` attribute, the deploy node
   name and the docs page name. The site decides the directory (`nixos/boxes/<site>/`), the
   constants block in [`lib/constants.nix`](../lib/constants.nix) it draws prefixes from, and the
   docs directory (`docs/sites/<site>/`, `docs/remote/`, `docs/mobile/`).
2. **Role** — what it does, which decides its modules, networking and firewall config.
3. **nixpkgs channel** — `unstable` / `stable` / `mine` / `mine-stable`; match the site's other
   boxes unless there is a reason not to.
4. **Networking** — whether it gets `assignments` now, or bootstraps on DHCP because it is being
   staged somewhere other than its final home. A box with no assignment still needs a reachable
   `my.deploy.node.hostname`, since the default (`config.networking.fqdn`) will not resolve.

## Phase 2 — Reach the installer and inventory the hardware

With the box booted into the installer and `INSTALLER` set:

1. Confirm you are talking to the right thing — `installer-shell hostname` reports `installer`, and
   `/etc/os-release` carries `VARIANT_ID=installer`.
2. Collect the inventory you will need for both the config and the docs page: `lscpu`, `free -h`,
   `lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,SERIAL`, `ip -br link`, `ip -br addr`,
   `lspci -nn | grep -Ei 'ethernet|network|nvme|sata|raid'`, and whether `/sys/firmware/efi` exists.
3. Record every NIC's **permanent MAC** against its PCI address — interface naming in Phase 5 pins
   names to MACs, and the PCI order tells you which physical port is which.
4. Run `installer-shell bash -lic show-hw-config` now for the kernel-module lists. Filesystems are
   not mounted yet, so run it again in Phase 4 for those.

## Phase 3 — Partition, format and mount

⏸ Destructive. Check the target disks are the ones you think they are and that nothing on them is
wanted, then show the exact command sequence and get confirmation before running it.

The house layout is a tmpfs root (`my.tmproot`) with three mounts: an ESP at `/boot`, `/nix`, and
`/persist` (`neededForBoot = true`). Use **`sgdisk`** for partitioning and put `/nix` and `/persist`
on **LVM** so they can be resized later:

```sh
sgdisk -Z /dev/<disk>
sgdisk \
  -n 1:0:+2G -t 1:ef00 -c 1:esp \
  -n 2:0:0   -t 2:8e00 -c 2:lvm \
  /dev/<disk>
partprobe /dev/<disk>

pvcreate /dev/<disk>p2
vgcreate main /dev/<disk>p2
lvcreate -L 48G      -n <host>-nix     main
lvcreate -l 100%FREE -n <host>-persist main

mkfs.vfat -n ESP /dev/<disk>p1
mkfs.ext4 -L nix     /dev/main/<host>-nix
mkfs.ext4 -L persist /dev/main/<host>-persist
```

Conventions worth keeping: volume group `main`, logical volumes `<host>-nix` / `<host>-persist`,
and ext4 filesystem labels `nix` and `persist`. Size the ESP and `/nix` to the box — 2 GiB and
48 GiB suit a small single-disk box.

Then mount everything under `$INSTALL_ROOT`, with a tmpfs standing in for the eventual tmpfs root:

```sh
mount -t tmpfs -o size=2G tmpfs "$INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT"/{nix,persist,boot}
mount /dev/main/<host>-nix     "$INSTALL_ROOT/nix"
mount /dev/main/<host>-persist "$INSTALL_ROOT/persist"
mount /dev/<disk>p1            "$INSTALL_ROOT/boot"
```

### Seed the SSH host key

The installer generates fresh host keys on every boot, so adopt them as the box's own rather than
letting it generate another set on first boot. Copy them onto the persist volume now:

```sh
install -d -m 0755 "$INSTALL_ROOT/persist/etc/ssh"
for t in ed25519 rsa; do
  install -m 0600 "/etc/ssh/ssh_host_${t}_key"     "$INSTALL_ROOT/persist/etc/ssh/ssh_host_${t}_key"
  install -m 0644 "/etc/ssh/ssh_host_${t}_key.pub" "$INSTALL_ROOT/persist/etc/ssh/ssh_host_${t}_key.pub"
done
```

`my.tmproot` persists `services.openssh.hostKeys` at exactly those paths, so the installed system
picks them up. This means the box's key is known **before** it first boots, so `my.secrets.key` can
be set and its secrets encrypted as part of the same pass — no install, boot, re-encrypt, re-deploy
round trip. (For a box already up, the `ssh-get-ed25519 <host>` devshell command prints the same
value in the form `my.secrets.key` wants.)

## Phase 4 — Capture the hardware config

Re-run `installer-shell bash -lic show-hw-config` with the filesystems mounted.

Read the whole generated file and carry over **anything** in it that the flake does not already
provide — it reflects what was actually detected on this hardware, and the list below is just what
usually shows up, not a limit:

- `boot.initrd.availableKernelModules` and `boot.initrd.kernelModules` (LVM adds `dm-snapshot`)
- `boot.kernelModules` (`kvm-intel` / `kvm-amd`) and the microcode attribute
- the ESP's `by-uuid` device, and the device paths for `/nix` and `/persist`
- anything else it emits — `boot.extraModulePackages`, `hardware.*` attributes, `swapDevices`,
  additional detected filesystems, `imports` such as `not-detected.nix`

The test is conflict, not familiarity: drop an option only when a nixfiles module already sets it,
and keep it otherwise. The flake's own modules cover the bootloader, `initrd.systemd`,
`initrd.services.lvm`, the kernel package and `nixpkgs.hostPlatform` (see
[`nixos/modules/common.nix`](../nixos/modules/common.nix) and
[`nixos/default.nix`](../nixos/default.nix)), so those are the ones to leave out. Don't paste the
file in wholesale either — translate it into the box's own style, and reference LVM volumes as
`/dev/main/<host>-nix` rather than the generated `/dev/mapper/main-<host>--nix`.

## Phase 5 — Write the box config

Create `nixos/boxes/<site>/<host>/default.nix` (a directory, so per-topic files can be added
alongside it later) declaring `nixos.systems.<host>`, and add its path to the `configs` list in
[`flake.nix`](../flake.nix). Then `git add` it.

The minimum is `system`, `nixpkgs`, `home-manager` and a `configuration` with the hardware from
Phase 4, the three filesystems, and networking. Beyond that:

- **Interface naming:** pin names to hardware with `.link` files matching `PermanentMACAddress`,
  named for speed and index — `et1g0`, `et2g5-0`, `et10g-1`. Never rely on predictable-interface
  names in the `.network` files.
- **Servers** set `my.server.enable = true`.
- **Secrets:** set `my.secrets.key` to the ed25519 public key seeded in Phase 3 (the key only, no
  `root@installer` comment). Note that **every box declares at least one secret** even if its own
  config declares none: [`nixos/modules/user.nix`](../nixos/modules/user.nix) adds
  `user-passwd.txt` whenever `my.user.enable` is on, which is the default. So setting
  `my.secrets.key` always adds the box to that file's recipients, and
  `ragenix --rekey-one secrets/user-passwd.txt.age` is required — skip it and the box cannot
  decrypt its user password on first boot. Confirm what the box actually declares with
  `nix eval .#nixosConfigurations.<host>.config.age.secrets --apply builtins.attrNames`, and
  re-encrypt each of those files the same way. Create any new secrets with `ragenix -e <path>`.
  Never use `--rekey`, which rewrites every secret in `secrets/`.
- **A box staged away from its final home** gets a bootstrap `.network` taking DHCP, plus
  `systemd.network.wait-online.anyInterface = true` so boot does not block on unpatched ports, and
  an explicit `my.deploy.node.hostname`. Comment it as temporary and say what replaces it.

Validate with `check-system <host>` and fix eval errors before going near the target.

## Phase 6 — Install

⏸ The maintainer may want to run this step themselves; ask rather than assume.

`do-install <host>` builds the system's `toplevel`, `nix copy`s the closure into the installer's
`$INSTALL_ROOT` store, points `/nix/var/nix/profiles/system` at it, touches `/etc/NIXOS`, and runs
`switch-to-configuration boot` with `NIXOS_INSTALL_BOOTLOADER=1`. It prompts for confirmation and
prints the target it resolved.

- `--no-bootloader` skips the bootloader install (for a box that boots by other means).
- `--no-substitute` copies everything from the local store instead of letting the target substitute.

## Phase 7 — First boot and post-install

1. Reboot the box off the installer and confirm it comes up: it should get its address, and
   `hostname` should be the system name. Its SSH host key is the one seeded in Phase 3, so it
   presents the same fingerprint the installer did.
2. **Secrets.** If Phase 5 set `my.secrets.key`, they already decrypt. [`secrets.nix`](../secrets.nix)
   computes the ragenix recipient list from that key at evaluation time, so nothing needs
   regenerating — but any secret added to the box later must be re-encrypted for the new recipient
   list with `ragenix --rekey-one <path>`, one file at a time. Never reach for `ragenix --rekey`:
   it rewrites every secret in `secrets/` and buries the actual change in churn.
3. **Deploy.** `deploy .#<host>` should now work over the `deploy` user. If the box is staged
   somewhere without its final DNS name, `deploy --hostname <address> .#<host>` overrides the node
   hostname for one run.

## Phase 8 — Document it

Per [`AGENTS.md`](../AGENTS.md), a new box means:

- a box page under the right docs directory, following the standard layout (H1 + one-line intro;
  `Source` / `Host` / `nixpkgs` bullets; hardware inventory; `## Role`; `## Network assignments`
  linking to [`networking.md#box-assignments`](networking.md#box-assignments), or a short
  explanation if it has none yet; one `##` per topic; `## Notable config files` last);
- a row in the site index `README.md` boxes table;
- affected prose in [`networking.md`](networking.md) — the assignment tables themselves are
  CI-generated, so write the prose and leave the tables alone;
- the site diagram in [`README.md`](README.md) if the box changes its layout.
