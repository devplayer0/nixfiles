# installer

The custom NixOS installer image used to bootstrap new boxes.

- **Source:** [`nixos/installer.nix`](../../nixos/installer.nix)
- **Host:** — (a build target, not a deployed box)

## Role

- Defines `nixos.systems.installer`, a minimal server system rendered as a bootable ISO via
  `config.my.buildAs.iso` (`my.asISO`); the same base can also be built as a kexec or netboot
  tree.
- Build it with the devshell commands: `build-iso installer` (or `build-kexec installer` /
  `build-netboot installer`). The `update-installer` command force-tags `installer` to
  trigger a release rebuild in CI.

## Image contents

- Broad hardware support (`my.build.allHardware` pulls in the nixpkgs all-hardware profile);
  EFI- and USB-bootable, zstd-compressed squashfs. Volume ID
  `jackos-<release>-<arch>`, menu label "/dev/player0 Installer", image base name
  `jackos-installer`.
- Root SSH with the deploy key authorized (`PermitRootLogin prohibit-password`); a random
  `installer-<hex>` hostname is set at boot.
- `INSTALL_ROOT=/mnt` in the session environment, plus a `show-hw-config` alias wrapping
  `nixos-generate-config --show-hardware-config --root $INSTALL_ROOT`.
- NixOS documentation enabled, NetworkManager available but not started at boot (run
  `systemctl start NetworkManager`, then `nmtui`), GC and memory-overcommit tuning for low-memory
  targets, LVM thin and NFS support.
- Identifies itself as `VARIANT_ID=installer` in `/etc/os-release`, and leaves the target's
  persistent pstore entries alone (`Unlink=no`) so an install doesn't evacuate them.
- No regular user (`my.user.enable = false`), no tmpfs-root management, no NAT, and not a
  deploy target (`my.deploy.enable = false`).

## Installing a box

The devshell's installer commands ([`devshell/install.nix`](../../devshell/install.nix)) drive
an install over SSH against a booted installer reachable at `$INSTALLER`:

- `installer-shell` — get a shell on the installer.
- `do-install <system>` — builds the system's toplevel, `nix copy`s the closure to the
  installer's `$INSTALL_ROOT` remote store, sets the system profile, touches `/etc/NIXOS`,
  and runs `switch-to-configuration boot` with `NIXOS_INSTALL_BOOTLOADER=1` (skip the
  bootloader with `--no-bootloader`, skip substitution with `--no-substitute`).
