# Upgrading nixpkgs

Procedure for the periodic upgrade of all four nixpkgs channels (`unstable`, `stable`, `mine`,
`mine-stable`) and home-manager. Written to be followed by a person or any coding agent; a
shared agent-skill entry point exists at `.agents/skills/upgrade-nixpkgs/`, but the steps below are
the canonical source.

The upgrade is **guided, not automated**: do the mechanical and investigative steps, but stop at
the judgment points (marked ⏸) — pushing the fork, resolving rebase conflicts, editing the
stable-channel configuration, choosing a new release codename, and deleting version guards. Report
findings and let the maintainer decide. Keep a running summary and present it before any push or
commit.

Work the phases in order; skip one only if explicitly scoped to a subset.

## Setup facts

- **Fork checkout:** `~/documents/projects/nixpkgs` — remotes `origin` (`devplayer0/nixpkgs`) and
  `upstream` (`NixOS/nixpkgs`). Confirm the path exists; if not, ask.
- **Fork branches:** `devplayer0` (tracks `nixos-unstable`) and `devplayer0-stable` (tracks the
  current NixOS stable). Each is a small stack of local patches rebased onto upstream.
- **Flake pins** in `flake.nix` (`inputs`):
  - `nixpkgs-unstable.url = "nixpkgs/nixos-unstable"`
  - `nixpkgs-stable.url = "nixpkgs/nixos-<STABLE>"` (e.g. `nixos-26.05`)
  - `nixpkgs-mine.url = "github:devplayer0/nixpkgs/devplayer0"`
  - `nixpkgs-mine-stable.url = "github:devplayer0/nixpkgs/devplayer0-stable"`
  - `home-manager-unstable.url = "home-manager"`
  - `home-manager-stable.url = "home-manager/release-<STABLE>"`
- **Devshell commands:** `update-nixpkgs` = `nix flake update nixpkgs-{unstable,stable,mine,mine-stable}`;
  `update-home-manager` = `nix flake update home-manager-{unstable,stable}`.
- **Validation:** prefer `check-system <host>` and `nix flake check --no-build` over full builds.

## Phase 1 — Determine the current NixOS stable

Do this first: everything downstream (the fork's `devplayer0-stable` rebase target, the `flake.nix`
stable pins) has to agree on one NixOS stable release, so establish it up front.

1. Find the latest NixOS stable release branch — check `git branch -r` on `upstream` for the newest
   `release-YY.NN`, or the NixOS release schedule.
2. Compare it to `<STABLE>` in the `flake.nix` `nixpkgs-stable` / `home-manager-stable` URLs.
3. **If they already match** (no new stable): note "stable is current" and carry `<STABLE>` into the
   later phases.
4. ⏸ **If a newer stable has cut:** stop and report the coordinated change set before proceeding —
   the pieces must all move to the same release together:
   - Rebase `devplayer0-stable` onto the new `upstream/release-YY.NN` (Phase 2 uses this target).
   - Edit `flake.nix`: `nixpkgs-stable.url` and `home-manager-stable.url` → the new release.
   - Choose a new `lib/default.nix` `versionOverlay` codename (Phase 4 updates it).
   - Bump each system's `stateVersion` / `home.stateVersion` only if the maintainer explicitly
     wants to — that is a separate, deliberate decision; never auto-bump.
   Don't edit `flake.nix` here without confirmation.

## Phase 2 — Rebase the nixpkgs fork

For **both** branches — `devplayer0` onto `upstream/nixos-unstable`, and `devplayer0-stable` onto
`upstream/release-<STABLE>` (the release established in Phase 1):

1. In `~/documents/projects/nixpkgs`, confirm a clean working tree (`git status`). If dirty, stop
   and report — don't stash silently.
2. `git fetch upstream --prune` and `git fetch origin --prune`. If the checkout has been idle a
   long time this fetch can be large and slow; let it finish.
3. Enumerate the patch stack before rebasing:
   `git log --oneline upstream/nixos-unstable..origin/devplayer0` (and the stable equivalent
   against `upstream/release-<STABLE>`). For each commit, check whether it has landed upstream or
   been superseded — e.g. `git log --oneline upstream/nixos-unstable -- <path>` or grep the
   upstream tree for the package/option. Note any patch that now looks redundant.
4. Rebase: `git switch devplayer0 && git rebase upstream/nixos-unstable` (and the stable branch
   onto `upstream/release-<STABLE>`).
   - ⏸ **Conflicts:** stop. Report which patch conflicts and against what upstream change; let the
     maintainer resolve, or drop the patch if it has been upstreamed.
   - Clean rebase: continue.
5. Summarize: which patches still apply, which are now redundant (candidate to drop), which
   conflicted.
6. ⏸ **Push:** only after confirmation. `git push --force-with-lease origin devplayer0
   devplayer0-stable` (force needed — rebase rewrites history).
7. Wait for the GitHub mirror used by the flake inputs to catch up with the primary fork remote.
   Compare the local branch tips with
   `git ls-remote https://github.com/devplayer0/nixpkgs.git refs/heads/devplayer0
   refs/heads/devplayer0-stable` and do not continue until both match. Updating sooner can leave
   `nixpkgs-mine` and `nixpkgs-mine-stable` pinned to the pre-rebase commits even though the push
   succeeded.

## Phase 3 — Update the pinned inputs

Run together (they move as a set):

```
update-nixpkgs
update-home-manager
```

Then show the `flake.lock` diff for the nixpkgs/home-manager entries so the old→new revisions are
visible.

## Phase 4 — Refresh kernels and release metadata

Update the repository values that deliberately move with nixpkgs upgrades:

1. In `lib/constants.nix`, inspect the kernel attributes available from the refreshed nixpkgs pins
   and update both explicit selections:
   - `kernel.lts` → the newest upstream long-term-support kernel carried by nixpkgs.
   - `kernel.latest` → the newest kernel series carried by nixpkgs.
   Keep explicit `pkgs.linuxKernel.packages.linux_X_Y` attributes rather than replacing them with
   moving aliases. Confirm both attributes exist in the unstable and stable package sets used by
   the boxes; if the newest choice is unavailable on stable, report that instead of breaking the
   shared constant.
2. In `lib/default.nix`, update the `versionOverlay` values:
   - Set the leading `YY.MM` in `trivial.release` to the current year and month. Preserve the
     `:u-${prev.trivial.release}` suffix.
   - If Phase 1 found a new NixOS stable release, ⏸ ask the maintainer to choose or approve a new
     `trivial.codeName`, then update it as part of the coordinated stable bump. Otherwise retain the
     existing codename.

Show these edits alongside the input changes in the upgrade summary.

## Phase 5 — Sweep version-gated behavior

The repo carries branch-conditional logic and TODOs keyed to specific nixpkgs versions; some become
removable after an upgrade, especially after a stable bump. Surface them:

```
grep -rn "versionAtLeast\|versionOlder\|when 2[0-9]\.[0-9][0-9]\|TODO.*2[0-9]\.[0-9][0-9]" \
  --include=*.nix nixos home-manager lib pkgs flake.nix
```

Known example: `nixos/modules/common.nix` carries a `# TODO: Remove if-else when 26.11 releases`
guard. For each hit, evaluate whether the now-current versions make the guard removable and list
candidates. ⏸ Don't delete guards without confirmation — some protect the still-supported stable.

## Phase 6 — Review remaining flake inputs

Don't blanket-update. Walk the other inputs deliberately:

1. List inputs and locked revisions from `flake.lock` (or `nix flake metadata`).
2. For each meaningful input (`libnetRepo`, `devshell`, `determinate-nix`, `ragenix`, `deploy-rs`,
   `impermanence`, and the packaged apps like `boardie`, `harmonia`, and `copyparty`),
   compare the locked revision to upstream and summarize notable changes (breaking changes,
   relevant fixes). Many inputs `follows` `nixpkgs-unstable` and already moved in Phase 3.
3. Propose a per-input update list with reasons; update the approved ones with targeted
   `nix flake update <input>`, not a global update.

## Phase 7 — Validate

1. `nix flake check --no-build` (broad eval; reproduces CI's cheap checks).
2. `check-system <host>` on a representative box, and one exercising the stable channel if the
   boxes mix channels. This must exercise the refreshed kernel constants on both channels.
3. Build the actual devshell with
   `nix build --no-link --print-out-paths .#devShells.x86_64-linux.default`. Evaluation does not
   build its dependencies, so it cannot catch packaging conflicts introduced by inputs such as
   Determinate Nix.
4. After the evaluations pass, run `build-system <host>` for one representative NixOS box. Prefer
   the local box when it is managed by this flake: its full closure is likely to exercise the most
   relevant packages, home-manager configuration and upgraded kernel. Build only; do not switch.
5. Report eval/build results honestly. On failure, surface the error and stop rather than papering
   over it.

## Wrap-up

Present a final summary: fork rebase outcome (patches kept/dropped/conflicted), whether a stable
bump is pending or was applied, kernel and release-metadata changes, the lock diff, version-gate
cleanup candidates, inputs updated, and validation results. Leave committing to the maintainer
unless asked; if committing, follow the repo's `area/scope: Capitalized summary` convention.
