---
name: install-box
description: >-
  Install a new NixOS box into this flake, from bare hardware booted into the custom installer
  through to a deployable system: probe the hardware, partition and format the disks, write the box
  config and flake entry, run do-install, and document the box. Use when the user wants to install,
  bootstrap, provision or add a new box/host/machine.
---

# Install a box

The canonical, agent-agnostic procedure lives in the repo at
[`docs/install-box.md`](../../../docs/install-box.md). Read it and follow the phases in order.

Key reminders (see the doc for the full steps):

- It is **guided, not automated** — stop at the ⏸ points: settling what the box actually is
  (Phase 1), wiping and partitioning disks (Phase 3), and running `do-install` (Phase 6). The user
  often wants to do the install step by hand.
- **Phase 1 is not derivable from the hardware.** Name, site, role, channel and whether the box gets
  assignments now all have to come from the user. Ask before writing files.
- **`show-hw-config` is a shell alias**, so it needs `installer-shell bash -lic show-hw-config`.
  Run it twice: once early for the kernel-module lists, once after mounting for the filesystems.
- **`git add` the new box directory before evaluating** — the flake reads through git, and an
  untracked path fails as "Path … is not tracked by Git" rather than as a Nix error.
- **Validate with `check-system <host>`**, not `build-system` — evaluation catches module and option
  errors cheaply.
- **Seed the SSH host key from the installer** (Phase 3) by copying `/etc/ssh/ssh_host_*` onto the
  persist volume. The installer regenerates them each boot, so they are safe to adopt, and it means
  `my.secrets.key` can be set and secrets encrypted before the install rather than after first boot.
- **Every box declares a secret even when its own config declares none** — `my.user` pulls in
  `user-passwd.txt` by default — so setting `my.secrets.key` always requires
  `ragenix --rekey-one secrets/user-passwd.txt.age`. Check with
  `nix eval .#nixosConfigurations.<host>.config.age.secrets --apply builtins.attrNames` rather than
  assuming there is nothing to do. Re-encrypt selectively; `ragenix --rekey` rewrites every secret
  in `secrets/` and drowns the real change in churn.
- Take **everything** useful out of `show-hw-config`, not just the modules and filesystems — drop an
  option only when a nixfiles module already sets it.
- Finish with Phase 8: box page, site index row, `networking.md` prose. Don't hand-edit anything
  between `<!-- ... -->` markers.
