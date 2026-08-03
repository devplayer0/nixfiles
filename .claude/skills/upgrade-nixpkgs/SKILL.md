---
name: upgrade-nixpkgs
description: >-
  Upgrade all four nixpkgs channels (unstable, stable, mine, mine-stable) and home-manager for this
  flake: check for a NixOS stable bump, rebase the devplayer0 nixpkgs fork against upstream, run the
  update commands, sweep version-gated TODOs, and review flake inputs. Use when the user wants to
  update/bump nixpkgs, refresh the pins, or do the periodic nixpkgs/home-manager upgrade.
---

# Upgrade nixpkgs

The canonical, agent-agnostic procedure lives in the repo at
[`docs/nixpkgs-upgrade.md`](../../../docs/nixpkgs-upgrade.md). Read it and follow the phases in
order.

Key reminders (see the doc for the full steps):

- It is **guided, not automated** — do the mechanical/investigative work but stop at the ⏸ points:
  pushing the fork, resolving rebase conflicts, editing the `flake.nix` stable pins, and deleting
  version guards. Report and let the user decide.
- **Check the current NixOS stable first** (Phase 1) — the fork's `devplayer0-stable` rebase target
  and the `flake.nix` stable pins must agree on one release.
- **Re-verify the patch stack against freshly fetched upstream**, not stale refs — enumerate it with
  `git log`, don't assume a remembered list (stale `upstream/*` refs make already-upstreamed commits
  masquerade as fork-only patches).
