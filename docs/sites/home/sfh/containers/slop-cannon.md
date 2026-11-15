# slop-cannon

Coding agents (Claude Code and Codex), driven from the phone or a browser through
[Paseo](https://github.com/getpaseo/paseo), running as a container on [`sfh`](../README.md).

- **Source:** [`nixos/boxes/home/palace/vms/sfh/containers/slop-cannon.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/slop-cannon.nix)
- **Host:** NixOS container on `sfh`
- **nixpkgs:** `mine`

## Role

- Runs the Paseo daemon and the agents it starts, all as the unprivileged user `slop-cannon`.
- Not a deploy-rs target (`my.deploy.enable = false`): it's rendered via `my.asContainer` and
  deployed with `sfh`.
- `sfh` gives the container a low `CPUWeight`, a `MemoryMax` and a larger `/tmp` tmpfs for agent
  scratch files; `/tmp` counts against the memory cap.

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `slop-cannon`).

A single MACVLAN interface, `host0` on `sfh`'s `ctrs-hi`, carries the `hi` assignment. Nothing
listens on it apart from SSH.

## Users

| User | Purpose |
|---|---|
| `slop-cannon` | Runs Paseo and the agents; no `wheel`, locked password, Dev's SSH key; home persisted; UID/GID pinned in `lib.my.c.ids` |
| `dev` | Administration (`doas`); the usual primary user |

Both have Dev's SSH key; connect with the shared `ssh` aliases `slop-cannon` and `slop-cannon-dev`
(see [SSH and first login](#ssh-and-first-login)).

## Paseo

A daemon (`paseo-server`) that starts and manages agents and serves a WebSocket API to the Paseo
app, the web UI and the `paseo` CLI. Claude Code runs through the Claude Agent SDK, using the
installed `claude` and its claude.ai login; Codex runs through `codex app-server`.

### Service

- The upstream `services.paseo` module (flake input `paseo`, pinned to a release, imported in
  `nixos/modules/common.nix`), with a package override for the web UI bug
  [getpaseo/paseo#7673](https://github.com/getpaseo/paseo/issues/7673).
- Runs as `slop-cannon`, so agents use that user's logins and settings, with `~/.paseo` as
  `PASEO_HOME`.
- The daemon password comes from the age secret `slop-cannon/paseo.env` (`PASEO_PASSWORD=…`). Read
  it with `ragenix -e secrets/slop-cannon/paseo.env.age`.
- The service is not restarted on deploy, so running agents aren't interrupted. Restart it by hand
  (`doas systemctl restart paseo`) to pick up a new config; stopping it stops its agents.
- Startup takes about a minute and a half while bundled plugins load; the daemon answers 503 until
  it is ready.

### Settings

`services.paseo.settings` is rewritten into `~/.paseo/config.json` on every start, so changes made
from the app don't survive a restart. It:

- disables the tools Paseo injects into agents (`daemon.mcp.injectIntoAgents = false`), which would
  let an agent change its own mode, answer its own permission prompts or open terminals;
- requires relay replay protection;
- turns off dictation and voice, which would otherwise download a large local speech model;
- hides providers other than Claude and Codex;
- adds a "Claude, accept edits" agent profile. Each provider's default mode is hardcoded upstream
  (Claude `auto`, Codex `auto-review`), and profiles are the only way to preset one.

### Connectivity

- The daemon listens on `127.0.0.1:6767` only. The phone app and the hosted web app at
  `https://app.paseo.sh` reach it through our relay on
  [`middleman`](../../../colony/shill/containers/middleman.md#paseo-relay) (`paseo-relay.nul.ie`).
- Traffic through the relay is end-to-end encrypted between the app and the daemon; the relay sees
  only addresses, timing and sizes. The pairing QR code or link is the trust anchor; treat it like a
  password. Switching relays means re-pairing.
- Push notifications go from the daemon to Expo's push service (`exp.host`), one outbound request
  per notification carrying its text.
- In a browser, open the link `paseo daemon pair` prints: it loads the hosted web app with our
  relay's address. The daemon's own web UI is off (`features.webUi.enabled` defaults to `false`);
  if enabled, it needs a secure context, so it would be reached through an SSH tunnel to
  `localhost` (`ssh -L 6767:127.0.0.1:6767 slop-cannon`).

### State

Paseo keeps only its own records in `~/.paseo`: `config.json`, the daemon keypair and local
credentials, one record per agent under `agents/`, registered projects and workspaces, and the git
worktrees it creates under `worktrees/`. Conversations stay in the providers' own stores: a Claude
agent is a normal session under `~/.claude/projects/`, a Codex agent a normal rollout under
`~/.codex/sessions/`.

## Repos, worktrees and jj

Repos live under `~/src` as colocated jj clones (see `slop-clone` below). Paseo only calls `git`:

- A `local` workspace runs the agent in the checkout itself; `jj` and Paseo's git views see the same
  changes. Use it for work you want to steer with `jj`.
- A worktree workspace is a `git worktree` under `~/.paseo/worktrees` on its own branch. Use it for
  unattended agents. Archiving it removes the worktree with `--force`, losing uncommitted work.
- Archiving a `local` workspace removes only Paseo's record; the folder is kept.
- Only one colocated working copy per repo is possible, so parallel jj-driven work needs separate
  clones.
- Don't run `jj` in a folder while an agent is mid-turn there: jj snapshots its partial edits.

## Terminal access

- The `paseo` CLI talks to the running daemon: `paseo ls`, `paseo logs -f <id>`, `paseo send <id>
  "…"`, `paseo permit ls|allow|deny`. It is command-line only, not a chat interface.
- A session can be taken over in the provider's own TUI by its ID: `claude --resume <session>` in
  the agent's folder, or `codex resume <session>`. `paseo import` goes the other way. This is a
  hand-off, not a shared view: stop the agent in Paseo first and don't type in both.

## Agent permissions

Paseo has the full rights of `slop-cannon`: anyone with the daemon password or a pairing can start
agents in any mode, answer prompts and open terminals. The boundaries are the container, the
unprivileged user and the approval broker in front of the deploy key.

- Claude Code and Codex come from the shared `my.agents` home-manager module.
- Claude's user settings deny raw `deploy`, `ssh-machine` and `.keys/`, and ask before
  `slop-deploy` / `slop-ssh`. These match command text, so they steer agents rather than enforce a
  boundary.
- Claude's managed settings (`/etc/claude-code/managed-settings.json`) repeat the `deny` rules and
  disable bypass mode; agents can edit `~/.claude` but not `/etc`. The app still lists Bypass, but
  choosing it fails.
- Codex stores its credentials in a file. Its command sandbox does not work inside nspawn yet:
  bubblewrap can't mount a fresh `/proc` in the container, so every Codex command fails outside
  full-access mode.
- Deploys and `ssh-machine` access are meant to go through an approval broker, which is not built
  yet; until then agents can't deploy.

## SSH and first login

`slop-cannon` is not a deploy node, so `ssh-machine` can't reach it; SSH to
`slop-cannon-ctr.h.nul.ie` directly. Never forward your SSH agent into the box: agents could use
it while you're logged in. As a last resort, `ssh-machine sfh` and
`doas machinectl shell root@slop-cannon`.

The box has one Git key, `~slop-cannon/.ssh/id_ed25519`, generated on first boot. Add its public key
in Gitea as a write-enabled deploy key on each repo agents may use. Commits are authored as Dev
through the shared Git config.

First login, once, over `ssh slop-cannon`:

1. `claude auth login` (a full login; `setup-token` tokens are not enough for every feature).
2. `codex login --device-auth`.
3. `paseo daemon pair`, then scan the QR code with the Paseo app. The pairing link carries the
   relay endpoint.
4. `slop-clone <owner>/<repo>` for each repo. It clones a colocated jj repo into `~/src/<repo>`,
   registers it with Paseo as a local workspace, and prints the box's public key if Gitea refuses
   the clone.

## Notable config files

- [`nixos/boxes/home/palace/vms/sfh/containers/slop-cannon.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/containers/slop-cannon.nix) —
  container system: users, Paseo, Claude settings, `slop-clone`.
- [`home-manager/modules/agents/default.nix`](../../../../../home-manager/modules/agents/default.nix) —
  shared Claude Code and Codex configuration.
- [`nixos/boxes/home/palace/vms/sfh/default.nix`](../../../../../nixos/boxes/home/palace/vms/sfh/default.nix) —
  the `sfh` side: container instance, MACVLAN, CPU, memory and `/tmp` limits.
