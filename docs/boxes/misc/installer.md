# installer

The custom NixOS installer image used to bootstrap new boxes.

- **Source:** [`nixos/installer.nix`](../../../nixos/installer.nix)

## Role

- Defines `nixos.systems.installer`, a minimal system whose `my.buildAs.*`
  outputs produce installable artifacts — primarily a bootable **ISO**
  (`isoImage`), and the same base is reused for kexec/netboot trees.
- Build it with the devshell commands (see [`AGENTS.md`](../../../AGENTS.md#commands)):
  - `build-iso installer`
  - `build-kexec installer` / `build-netboot installer`
- A released ISO is what `colony`'s VM definitions reference as install media; the
  `update-installer` devshell command tags a release to trigger a rebuild.

This is a build target rather than a deployed machine — there is no running
`installer` host.
