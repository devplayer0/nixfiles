# slop-broker

[`slop-broker`](https://git.nul.ie/dev/slop-broker) carries out privileged operations (SSH
commands, deploys, builds, and later secrets, DNS and previews) for the coding agents on
[`slop-cannon`](sites/home/slop-cannon.md) and other boxes, under a policy and usually after Dev
approves each one. Agents use the `slop` CLI.

The broker, its NixOS and home-manager modules, its design and the agents' guide live in its own
repository, which this flake takes as the `slop-broker` input. This page covers how these boxes use
it; for how it works, read the repository's
[design](https://git.nul.ie/dev/slop-broker/src/branch/main/docs/design.md).

## In this flake

- **Input:** `slop-broker` in [`flake.nix`](../flake.nix). Its overlay provides `pkgs.slop-broker`,
  and the common modules import `services.slop-broker`, `services.slop-broker-builder`,
  `services.slop-broker-cache` and `programs.slop`. Update it with `nix flake update slop-broker`.
- **Persistence:** [`tmproot.nix`](../nixos/modules/tmproot.nix) keeps `/var/lib/slop-broker` and
  the builder's home when those services are enabled.
- **Agents:** `my.agents.slop` (in the shared `agents` home-manager module) installs `slop` and adds
  the guide (`share/slop-broker/slop-tools.md`) as a Claude rule (`~/.claude/rules/slop.md`) and
  as Codex's `AGENTS.md`.
- **Devshell:** `slop` and `slop-approve`, built from the locked input. `slop` uses
  `.keys/slop-request.key` over SSH when that file exists; an approver key never goes in `.keys/`,
  because agents can read the checkout.
