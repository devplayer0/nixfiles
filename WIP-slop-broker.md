# slop-broker: working notes (WIP, not for merge)

Notes for whoever picks up `slop-broker` next in this flake: where the work stands, what was
decided, and what comes next. They live in their own change at the top of the `slop-broker`
bookmark and are not meant to land. Durable facts go in [`docs/slop-broker.md`](docs/slop-broker.md)
and the box pages; drop this file when the work is done.

The broker itself is developed in its own repository, <https://git.nul.ie/dev/slop-broker> (local
checkout `../slop-broker`): code, modules, design (`docs/design.md`), architecture and gotchas
(`docs/architecture.md`), and a demo. Change it there, push, then `nix flake update slop-broker`
here.

`flake.lock` pins `21c2d471`, the broker's `main` after its history was cleaned up
(2026-11-24), so no override is needed any more. `palace` still runs `4e4c68cb`, deployed with one;
deploy it from this stack with plain `deploy .#palace`. Since then `palace` lists no SSH targets,
because the broker reads the deploy-rs nodes on `master` through its builder. Tested from `castle`
with queries to `estuary` and `river` (the first lookup takes about 15 s, then they're cached per
`master` commit) and an unknown node.

## Progress

As of 2026-11-24. The `slop-broker` bookmark, oldest first, on top of `master`, pushed to Gitea
(up to the castle change reviewed, not merged; the secrets changes wait for Dev's review). It
replaced the older stack that had the broker under `pkgs/slop-broker`, which is deleted.

| Change | State |
|---|---|
| `AGENTS.md: Spell out blank lines inside functions` | Done; unrelated to the broker, but sits at the bottom. |
| `nixos/middleman: Move Paseo web app to slop.nul.ie` | Done. `slop.nul.ie` and `*.slop.nul.ie` are CNAMEs to `http.int.nul.ie` in Cloudflare, and the certificate covers the wildcard. |
| `nixos/middleman: Add Pocket ID at id.nul.ie` | Done and deployed. Dev is the admin; the admin API key is `.keys/pocket-id.key`. Pocket ID has the group `slop-approvers` (Dev) and the confidential client `slop-approve` (PKCE, restricted to that group), whose secret is `palace/slop-broker-oidc-secret`. |
| `flake: Add slop-broker from its own repository` | The input (locked to `9f989b78`), overlay and modules; tmproot persistence, `my.agents.slop`, devshell commands, `docs/slop-broker.md`. |
| `nixos/palace: Run slop-broker for agents` | All of `palace`'s broker config, `object`'s cache key, and the `approve.slop.nul.ie` vhost on `middleman`. Targets come from `master`; deploys to `river`, `stream` and `estuary` need a passkey. `slop-cannon`'s Claude rules no longer deny `.keys/`, which only has public keys there. |
| `nixos/castle: Use slop-broker over SSH` | `castle`'s `programs.slop` setup, and its requester and approver keys on `palace`. |
| `secrets: Add slop-broker as a recipient` | `.keys/slop-broker.pub` in `defaultKeys`, and the one full rekey; nothing else, so the churn is on its own. |
| `nixos/palace: Let slop-broker change secrets` | The identity (`palace/slop-broker-age.key`), `services.slop-broker.secrets`, the `secret` policy (`keys` auto, others ask with a 5m lease), `lib.my.c.ageKeyFiles`, docs. Deployed to `palace`. |
| `WIP: slop-broker working notes (not for merge)` | This file. Keep it at the top. |

Deployed from this bookmark on 2026-11-23: `palace` (with the approvals web app) and
`shill.container-middleman` (with the `approve.slop.nul.ie` vhost), and `river` through `slop
deploy`. Deployed from the old stack: `object`, and `slop-cannon` (`--boot` through `slop deploy`,
before its permissive defaults). `castle` is switched to an earlier state locally (`deploy
.#castle` fails host key verification against itself, so use `build-n-switch switch`). Tested end
to end: queries, `slop ssh`, deploys, builds (including a real upload of 1181 paths), builder
leases and the egress filter.

The web app is tested on Dev's Android phone: Web Push notifications, answering from a
notification's buttons with the app closed, a builder approval, and a passkey approval for the
`river` deploy (logged as `web, passkey`). Only `middleman` reaches port 8095 on `palace`. The
`localhost` callback is gone from the `slop-approve` client. The old builder copy
(`nixfiles.git`) on `palace` is deleted.

Secrets (slop-broker `9f989b78`, `ops: Add age secrets`) are deployed to `palace` and tested end to
end from `castle`: `keys` (auto), `set` creating a file and editing it, `generate --kind
wireguard` and `read`, all approved from the phone and checked with the dev key. Until the stack
is merged, every file in a checkout shows as "not on master" (they were rekeyed on this branch),
and `master`'s files and `secrets.nix` don't include the broker yet, so `keys`, `read` and `rekey`
only work on files from this branch. The demo has no builder, so it has no secrets yet.

Not deployed: `slop-cannon`'s permissive agent defaults.

The repository's `main` (now `f94ad9ab`; CI runs `nix flake check` on every push) was rewritten on
2026-11-23, so every commit builds and passes its tests on its own:

- The web app's pages are askama templates (`templates/`), escaped through `ops::printable`;
  sessions are in SQLite (`sessions.sqlite`) instead of `sessions.json`, so anyone signed in signs
  in again once, and a leftover `sessions.json` in the web state directory can be deleted.
- `libc` is replaced by the `nix` crate (already a dependency) and `File::try_lock`.
- The "drop assumptions from one deployment" commit is folded into the commits that introduced
  each line, so no commit names `nul.ie` or defaults to `doas` (some test fixtures still use box
  names, which is fine).
- `nix develop` gives a plain shell besides devenv, without the demo or devenv's scripts.
- Looked at and left alone: Web Push (the `web-push` crate does the work), the policy glob,
  duration parsing. `ha.rs` is now gone too (`2af7c55a`).

## Decisions (2026-11-22)

- **Approvals web app:** public at `approve.slop.nul.ie`, signing in through **Pocket ID** at
  `id.nul.ie` (passkey-only OIDC) with the broker as its own OIDC client, optional per-request
  passkeys through OIDC re-authentication (`max_age=0`, checking `auth_time`), and **Web Push**.
- **No passkeys in the broker itself.** Tested with a temporary public PKCE client: `max_age=0`
  and `prompt=login` both prompted for a passkey and returned a fresh `auth_time`, while a plain
  request reused the existing session's.
- **Agents on `castle`** can use the approver's session or `castle`'s SSH approver key; Dev
  accepts that, since agents should mostly run on `slop-cannon`.
- **Home Assistant** notifications are gone (2026-11-24), replaced by the web app's Web Push;
  rewritten out of this stack, and `ha.rs` dropped from the broker.
- **`slop-cannon` agents are permissive by default** (Claude `bypassPermissions`, Codex
  `approval_policy = "never"` and `danger-full-access`, matching Paseo profiles); the deny rules
  and the agent guide still steer towards `slop`.
- **Later, a separate `middleman` project:** move the private vhosts from `nginx-sso` (Google
  OAuth) to oauth2-proxy against Pocket ID, and apps with native OIDC (Gitea, HedgeDoc, MinIO,
  Synapse) to Pocket ID directly; then previews' `--auth sso` follows.
- **Agents open PRs as a Gitea bot user** (2026-11-24): a user (say `slop`) with write access to
  the repositories agents use replaces `slop-cannon`'s deploy key, with a token scoped
  `write:repository` and `write:issue` as an age secret for `slop-cannon`, so agents can open,
  update and comment on PRs (API or `tea`). It's safe in the VM only because `master`'s protection
  lets Dev alone push and merge. Rejected: AGit pushes (`refs/for/master`) with the deploy key,
  which may not be allowed for deploy keys and can't comment or edit.

## Next, in order

1. **Deploy the other boxes** at leisure; the rekeyed files decrypt to the same values. `palace`
   and `slop-cannon` are done.
2. **Delete the `slop-broker` user** and its long-lived token on `hass` (Dev, in the UI).
3. **Redeploy `slop-cannon`** for the bot's new token (with `read:user`; on `master`), then check
   `tea whoami` there. Gitea is set up (2026-11-25): the old deploy key is gone, slop-broker's
   `main` is protected like nixfiles' `master`, and agents push as the bot over HTTPS, with pull
   requests as their default.
4. DNS, previews and forwards: the rollout in [`docs/slop-broker.md`](docs/slop-broker.md).

## Web app follow-ups

All of these are on slop-broker `main` (`f94ad9ab`), locked here and deployed to `palace`:

- `web: Scroll the audit log sideways on phones`: `table.log` gets a `min-width`, so its `.scroll`
  wrapper scrolls instead of squeezing the columns.
- `web: Ask for the passkey on every sign-in`: signing out only ended the app's session, and the
  next sign-in went straight through `id.nul.ie`'s own session. Every sign-in now sends
  `max_age=0` and checks `auth_time`, like passkey confirmations. Chosen over ending the Pocket ID
  session too (RP-initiated logout), which would sign out of every app using Pocket ID.
- `web: Give form controls one consistent style`: selects, text fields and buttons share one
  look, and the log's filters stack their labels and wrap into rows on a phone.
- `web: Brand the app as Slopprovals`: the name, and Noto Emoji's thinking face in the icon.

## Working on it

- Workspaces: this one (`nixfiles-jj3`, with `.keys/`), `../nixfiles-deploy-broker` (no private
  keys, for trying `slop` as an agent would), `default` (`../nixfiles-jj`) and `../nixfiles-jj2`.
  Each workspace's working copy is an empty, undescribed change: don't abandon by a revset that
  could match another workspace's.
- jj doesn't create local bookmarks for new remote branches: after `jj git fetch`, use
  `jj new <bookmark>@origin` or `jj bookmark track <bookmark>@origin`.
- Claude Code's permission check refuses using the broker's deploy key directly (for example to
  test a command by hand on `palace`); test through the broker, or ask Dev.
- In `../slop-broker`, pushed commits are immutable to jj; rewriting them needs
  `--ignore-immutable` and a force-push.
