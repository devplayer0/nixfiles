# Upgrading nixpkgs

Procedure for the periodic upgrade of all four nixpkgs channels (`unstable`, `stable`, `mine`,
`mine-stable`) and home-manager. Written to be followed by a person or any coding agent; a
shared agent-skill entry point exists at `.agents/skills/upgrade-nixpkgs/`, but the steps below are
the canonical source.

The upgrade is **guided, not automated**: do the mechanical and investigative steps, but stop at
the judgment points (marked ⏸) — pushing the fork, resolving rebase conflicts, editing the
stable-channel configuration, choosing a new release codename, deleting version guards, and
choosing how to handle a service or package that no longer works on its current channel. Report
findings and let the maintainer decide.

Work the phases in order; skip one only if explicitly scoped to a subset.

## Progress document

Maintain `docs/nixpkgs-upgrade-progress.md` in the upgrade workspace. It is a working record, not
part of the upgrade's history: keep it in the topmost working-copy change, out of the commits that
make up the upgrade series, and delete it at [wrap-up](#wrap-up). At the start, record the baseline
revision, target channels, and scope. On resume, read it first and verify its revisions and
completed steps against the working copy, lockfile, and remote refs.

Update the document as each phase finishes and before a push, commit, or handoff. Include the
reviewed revision or version ranges, links to changelogs or commits, the practical effect on this
repo, and any unreviewed items. Record the decisions made and pending, including alternatives,
the rationale for a fix or workaround, and the condition for removing a temporary pin or
mitigation. Mark inherited choices separately from maintainer approvals. Record validation results
against the candidate revisions and leave a concrete next step for any outstanding work.

## Setup facts

- **Fork checkout** defaults to `../nixpkgs` relative to this flake's root. Verify `origin` points
  to the `devplayer0/nixpkgs` fork and `upstream` to `NixOS/nixpkgs`. Ask for the location if needed.
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
- **Validation:** prefer `check-system <host>` while iterating and reserve the flake check for final validation.

## Phase 1 — Determine the current NixOS stable

Do this first: everything downstream (the fork's `devplayer0-stable` rebase target, the `flake.nix`
stable pins) has to agree on one NixOS stable release, so establish it up front.

1. Check the [NixOS stable release notes](https://nixos.org/manual/nixos/stable/release-notes.html)
   and the release schedule. A `release-YY.NN` branch can exist during stabilization before that
   release becomes the published stable channel.
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

1. In the fork checkout, confirm a clean working tree (`git status`). If dirty, stop
   and report — don't stash silently.
2. Fetch the branches explicitly. Some fork checkouts fetch only `master` from `upstream` by default.
   Set `stable` to the release established in Phase 1.

   ```sh
   git fetch upstream \
     +refs/heads/master:refs/remotes/upstream/master \
     +refs/heads/nixos-unstable:refs/remotes/upstream/nixos-unstable \
     "+refs/heads/release-${stable}:refs/remotes/upstream/release-${stable}" \
     "+refs/heads/nixos-${stable}:refs/remotes/upstream/nixos-${stable}"
   git fetch origin --prune
   ```

   The `release-${stable}` branch is the stable fork's rebase base. The published `nixos-${stable}`
   branch is the source for the stock stable flake input and can lag behind it.
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
5. If the upgrade includes requested upstream fixes, verify them on each new base. Cherry-pick
   only where the fix is missing and use `git cherry-pick -x` to record the source commit. Check the
   resulting package versions or patches on both fork branches and on the published channels.
6. Run `git range-diff <old-base>..<old-tip> <new-base>..<new-tip>` for both branches. Use the
   fork's previous upstream bases for the old ranges. Present the comparison before asking to push,
   identifying unchanged, modified, dropped, and added patches. For dropped or modified patches,
   give the reason and cite the superseding upstream commit when applicable.
7. ⏸ **Push:** only after confirmation. `git push --force-with-lease origin devplayer0
   devplayer0-stable` (force needed — rebase rewrites history).
8. Wait for the GitHub mirror used by the flake inputs to catch up with the primary fork remote.
   Compare the local branch tips with
   `git ls-remote https://github.com/devplayer0/nixpkgs.git refs/heads/devplayer0
   refs/heads/devplayer0-stable` and do not continue until both match. Updating sooner can leave
   `nixpkgs-mine` and `nixpkgs-mine-stable` pinned to the pre-rebase commits even though the push
   succeeded.

## Phase 3 — Update nixpkgs and home-manager pins and review compatibility

Run together (they move as a set):

```
update-nixpkgs
update-home-manager
```

Then show the `flake.lock` diff for the nixpkgs/home-manager entries so the old→new revisions are
visible.

Review the NixOS and home-manager modules and packages used by this repo against the previous and
candidate pins for their assigned channels. Use release notes and version and option changes to
identify removals, end-of-life versions, major upgrades, and changed defaults. Include packages
selected by service modules and local overrides. Prioritize stateful services and check upstream
migration notes for data formats, supported upgrade paths, extensions, and client compatibility.
Record the affected boxes, versions, and any action needed before switching. Surface changes that
could break a running app even if its configuration evaluates and builds.

⏸ Discuss channel moves or migrations with the maintainer before editing the affected service.
Use the compatibility decision in Phase 7 for any blockers found here.

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

1. List all direct inputs with their locked revisions and configured refs. Include fixed release
   tags, fork branches, and non-GitHub inputs. Identify which inputs already follow one of the
   refreshed nixpkgs pins and which carry independent pins.
2. Compare each locked revision with the candidate revision on the configured branch or release
   track. Review the intervening changelog, release notes, advisories, and changes to the interfaces
   this repo uses. Summarize relevant fixes, breaking changes, and required configuration or build
   changes. Report any comparison you could not complete.
3. Refresh the moving inputs and applicable release pins in the main upgrade with targeted
   `nix flake update <input>` commands. Verify the resulting lock revisions against the reviewed
   candidates, especially if the fetcher used cached refs. ⏸ Ask before switching release tracks,
   changing an intentional compatibility pin, or deferring an update that needs a migration.

## Phase 7 — Validate

1. `nix flake check --no-build` for broad validation. If `.#ciIfdReasons.x86_64-linux` lists
   an active exception, use `nix flake check` so evaluation can build the required inputs.
2. `check-system <host>` on a representative box, and one exercising the stable channel if the
   boxes mix channels. This must exercise the refreshed kernel constants on both channels.
3. Build the actual devshell with
   `nix build --no-link --print-out-paths .#devShells.x86_64-linux.default`. Evaluation does not
   build its dependencies, so it cannot catch packaging conflicts introduced by inputs such as
   Determinate Nix.
4. After the evaluations pass, run `build-system <host>` for one representative NixOS box. Prefer
   the local box when it is managed by this flake: its full closure is likely to exercise the most
   relevant packages, home-manager configuration and upgraded kernel. Build only; do not switch.
5. Fix mechanical compatibility errors that preserve service behavior. ⏸ If a package was removed,
   reached end of life, or needs a major upgrade, explain the choices before editing the affected
   service. Include the current configured version, the deployed version if verified, and the
   available paths, such as a temporary channel move, a migration during this upgrade, or a
   separate service change. Describe effects on persisted data, dependent services, cutover, and
   rollback where relevant. Ask for a decision for each affected service and continue independent
   validation while waiting. If the maintainer chooses a temporary pin, add a TODO beside it naming
   the deferred migration and the condition for removing the pin.
6. Report eval/build results and any blockers. A build confirms that the configuration compiles.
   Confirm the migration prerequisites separately before deployment.

## Wrap-up

Present a final summary: fork rebase outcome (patches kept/dropped/conflicted), whether a stable
bump is pending or was applied, kernel and release-metadata changes, the lock diff, version-gate
cleanup candidates, inputs updated, and validation results. Leave committing to the maintainer
unless asked; if committing, follow the repo's `area/scope: Capitalized summary` convention.

Split the series into the procedure or skill changes, the pin and input refresh, and a separate
change for each service migration done during the upgrade. The refresh's description lists the
notable upgrades: kernels, stateful services that migrate data, other major version moves and
significant flake input releases, with old and new versions. This keeps the version history
readable in `jj log` after the progress document is gone.

Once the upgrade is deployed, move anything still open in the progress document to its durable
home: a TODO beside the pin or workaround it concerns, the affected box page, or a commit
message for a decision worth keeping. Then delete the progress document. The next upgrade starts
from those TODOs and pages rather than from an old progress document.
