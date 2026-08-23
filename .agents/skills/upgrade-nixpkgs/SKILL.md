---
name: upgrade-nixpkgs
description: >-
  Upgrade all four nixpkgs channels (unstable, stable, mine, mine-stable) and home-manager for this
  flake: check for a NixOS stable bump, rebase the devplayer0 nixpkgs fork, update kernel and
  release metadata, refresh pins, sweep version-gated TODOs, and review other inputs. Use when the
  user wants to update/bump nixpkgs, refresh the pins, or do the periodic nixpkgs/home-manager
  upgrade.
---

# Upgrade nixpkgs

Read [`docs/nixpkgs-upgrade.md`](../../../docs/nixpkgs-upgrade.md), the canonical procedure, and
follow its phases in order.

Key reminders (see the doc for the full steps):

- It is **guided, not automated** — do the mechanical and investigative work but stop at the ⏸
  points: pushing the fork, resolving rebase conflicts, applying a stable-channel bump, choosing a
  new release codename, and deleting version guards. Report the findings and let the user decide.
- **Check the current NixOS stable first** (Phase 1) — the fork's `devplayer0-stable` rebase target
  and the `flake.nix` stable pins must agree on one release.
- **Re-verify the patch stack against freshly fetched upstream**, not stale refs — enumerate it with
  `git log`; don't assume a remembered list.
- After refreshing the pins, update `lib/constants.nix` to the current explicit LTS and latest
  kernel package attributes, and update the `lib/default.nix` version overlay's `YY.MM` prefix to
  the current month. Change its codename only when the stable channel advances.
