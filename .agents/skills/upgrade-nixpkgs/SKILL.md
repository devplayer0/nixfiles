---
name: upgrade-nixpkgs
description: >-
  Upgrade all four nixpkgs channels (unstable, stable, mine, mine-stable) and home-manager for this
  flake: check for a NixOS stable bump, rebase the devplayer0 nixpkgs fork, update kernel and
  release metadata, refresh pins, sweep version-gated TODOs, and review compatibility of nixpkgs
  apps and services and other flake inputs. Use when the user wants to update/bump nixpkgs,
  refresh the pins, or do the periodic nixpkgs/home-manager upgrade.
---

# Upgrade nixpkgs

Read [`docs/nixpkgs-upgrade.md`](../../../docs/nixpkgs-upgrade.md), the canonical procedure, and
follow its phases in order.

Key reminders (see the doc for the full steps):

- Read and update the progress document, `docs/nixpkgs-upgrade-progress.md`, as you work.
  On resume, reconcile it with the working copy and remote refs. Record what was reviewed,
  what was approved, the reason and exit condition for each workaround, and the next open step.
  Keep it out of the upgrade's commits. At wrap-up, move open follow-ups to TODOs, box pages or
  commit messages, then delete it.
- Commit the pin and input refresh separately from procedure changes and from each service
  migration, and list the notable version upgrades in the refresh's description.
- It is **guided, not automated** — do the mechanical and investigative work but stop at the ⏸
  points: pushing the fork, resolving rebase conflicts, applying a stable-channel bump, choosing a
  new release codename, deleting version guards, and choosing how to handle service compatibility
  blockers. Present channel moves and migrations as choices before making either change.
  If a temporary pin is chosen, add a TODO for the deferred migration.
- **Check the current NixOS stable first** (Phase 1) — the fork's `devplayer0-stable` rebase target
  and the `flake.nix` stable pins must agree on one release.
- Use `../nixpkgs` relative to this flake's root as the default checkout of the
  `devplayer0/nixpkgs` fork.
- **Fetch the upstream branches explicitly** and re-verify the fork patch stack with `git log`.
  Check for requested backports on each rebase base before cherry-picking them.
  Compare both patch stacks with `git range-diff` and summarize the changes before asking to push.
- After pushing the rebased fork branches, **wait for the GitHub mirror to catch up** before
  refreshing flake pins. The `nixpkgs-mine*` inputs fetch from GitHub, not the fork's primary
  remote; verify both GitHub branch tips match the pushed local tips first.
- After refreshing the pins, update `lib/constants.nix` to the current explicit LTS and latest
  kernel package attributes, and update the `lib/default.nix` version overlay's `YY.MM` prefix to
  the current month. Change its codename only when the stable channel advances.
- Review the apps and services supplied by each nixpkgs channel in use (Phase 3). Compare the old
  and candidate versions and module options, and check release notes for removals, changed defaults,
  compatibility with persisted data, and migrations that evaluation may miss.
- Compare each direct flake input's pin with its candidate for fixes and breaking changes.
  Include the refreshes in the main upgrade. Ask before changing the release track, moving an
  intentional compatibility pin, or deferring an update that needs a migration.
- After the cheap evaluations pass, build the actual devshell and one representative NixOS system
  (prefer the local box). `nix flake check --no-build` does not expose dependency build failures;
  this is especially important when updating build-tool inputs such as Determinate Nix.
