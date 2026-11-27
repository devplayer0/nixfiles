# slop-cannon

Coding agents (Claude Code and Codex), driven from the phone or a browser through
[Paseo](https://github.com/getpaseo/paseo), running in a VM on [`palace`](palace.md) with root
inside it.

- **Source:** [`nixos/boxes/home/palace/vms/slop-cannon.nix`](../../../nixos/boxes/home/palace/vms/slop-cannon.nix)
  (the VM itself in [`palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix))
- **Host:** VM on `palace`
- **nixpkgs:** `mine`

## VM resources

| vCPUs | RAM | Disk | Network | Other |
|---|---|---|---|---|
| 16c × 2t (overcommitted) | 24 GiB | 512 GiB virtio, NVMe-oF from `cellar` via `palace` | SR-IOV VF 5 (`44:00.6`) on VLAN 120 | installer ISO |

`vm@slop-cannon` has a low `CPUWeight` on `palace`, so `cellar`, `river` and `sfh` win under
contention. `palace` has `kvm_amd` `nested=1`, so the guest has `/dev/kvm`.

## Role

- Runs the Paseo daemon and the agents it starts, as the user `slop-cannon`. Agents have root in
  the VM (`wheel`, passwordless `doas`): nested VMs, kernel modules, system services.
- A normal deploy node (`deploy .#slop-cannon`, `ssh-machine slop-cannon`).
- Everything inside the guest is treated as agent-controlled. The boundaries are outside it:
  the `untrusted` filter on the routers, the VLAN tag on the NIC and the disk connection on
  `palace`. Credentials for deploying or logging into other boxes stay outside the VM, with
  [`slop-broker`](../../slop-broker.md) on `palace`.

## Network assignments

See the consolidated [network assignments](../../networking.md#box-assignments) table (this box:
`slop-cannon`).

## Network

- The only interface, `lan-untrusted`, is SR-IOV VF 5 on `palace`. The NIC tags and filters VLAN
  120 and enforces MAC spoof checking on the host side. The guest loads `mlx5_core` at boot.
  See the [VF attachment table](palace.md#connectx-4-vfs).
- A static `untrusted` address (outside both routers' DHCP pools), MTU 1500. DNS is Cloudflare,
  as `untrusted`'s DHCP and RAs hand out; the routers' resolvers aren't reachable from
  `untrusted`.
- The routers keep `untrusted` to the Internet (see
  [Untrusted clients](../../networking.md#untrusted-clients)). `git.nul.ie` and
  `paseo-relay.nul.ie` resolve to colony IPv6 addresses, which are rejected, so Gitea and the
  Paseo relay fall back to IPv4 immediately.
- SSH from `hi` and `lo` works through the routers. The VM shares layer 2 with other clients
  on the `untrusted` VLAN.
- Builds use the guest's own Nix daemon and store, behind the same filter.

## Storage

- One virtio disk: GPT with a 2 GiB ESP (partition label `esp`) and an LVM PV in VG `main`.
- `slop-cannon-nix`, `slop-cannon-persist` and `slop-cannon-tmp` are thin LVs in `main/tpool`,
  overcommitted, so space goes to whichever needs it. The pool takes 90% of the VG; LVM grows it
  into the rest at 80% full (`thin_pool_autoextend_threshold`). Watch `lvs` if it gets close.
- The root is `tmproot`; `/tmp` is its own LV, cleaned on boot and mounted with `discard`, so
  agents' scratch files don't use RAM and freed space returns to the pool.
- The disk is `nqn.2016-06.io.spdk:slop-cannon` on [`cellar`](cellar.md), connected by `palace`
  (see [`palace`'s disk notes](palace.md#slop-cannons-disk)). The guest never speaks NVMe-oF.

## Users and secrets

| User | Purpose |
|---|---|
| `slop-cannon` | Runs Paseo and the agents; `wheel` and `kvm`; locked password, Dev's SSH key; home persisted; UID/GID pinned in `lib.my.c.ids` |
| `dev` | Administration; locked password, Dev's SSH key |

- No `user-passwd.txt` (`my.user.passwordSecret = null`): root belongs to the agents, so the box
  gets no shared secrets. Recovery is through the installer ISO.
- The VM's SSH host key is the age identity for `slop-cannon/paseo.env` and
  `slop-cannon/gitea-token`. Agents can read the host key and decrypt anything encrypted to it.

## Paseo

A daemon (`paseo-server`) that starts and manages agents and serves a WebSocket API to the Paseo
app, the web UI and the `paseo` CLI. Claude Code runs through the Claude Agent SDK, using the
installed `claude` and its claude.ai login; Codex runs through `codex app-server`.

### Service

- The `services.paseo` module from our Paseo fork (flake input `paseo`, imported in
  `nixos/modules/common.nix`), with a package override for the web UI bug
  [getpaseo/paseo#7673](https://github.com/getpaseo/paseo/issues/7673).
- The fork, [`dev/paseo`](https://git.nul.ie/dev/paseo), adds support for colocated Jujutsu
  repositories: Jujutsu workspaces, change views and actions in the app, and
  `paseo workspace jj` in the CLI. Each `fork/jujutsu-v<version>` branch carries the fork commits
  on an upstream release; `main` mirrors upstream. The branch's `docs/jujutsu-fork.md` explains
  the controls and how to rebase the fork.
- The fork also compacts an idle Claude agent with a large context shortly before its one-hour
  prompt cache expires, as Claude Code does in a terminal. It is on by default and set with
  `agents.idleCompaction` (see the fork's `public-docs/configuration.md`).
- The daemon runs the `jj` from the system and user profiles on its `PATH`.
- Runs as `slop-cannon`, so agents use that user's logins and settings, with `~/.paseo` as
  `PASEO_HOME`.
- The daemon password comes from the age secret `slop-cannon/paseo.env`. To read it for a new
  client, follow [Pair a Paseo client](#pair-a-paseo-client).
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
- adds "Claude, bypass permissions" and "Codex, full access" agent profiles. Each provider's
  default mode is hardcoded upstream (Claude `auto`, Codex `auto-review`), and profiles are the
  only way to preset one, so pick a profile when starting an agent for the permissive mode.

### Connectivity

- The daemon listens on `127.0.0.1:6767` only. The phone app and the browser reach it through our
  relay on [`middleman`](../colony/shill/containers/middleman.md#paseo-relay)
  (`paseo-relay.nul.ie`).
- Traffic through the relay is end-to-end encrypted between the app and the daemon; the relay sees
  only addresses, timing and sizes. The pairing QR code or link is the trust anchor; treat it like a
  password. Switching relays means re-pairing.
- Push notifications go from the daemon to Expo's push service (`exp.host`), one outbound request
  per notification carrying its text.
- `middleman` serves the static web app on `slop.nul.ie`. The daemon's own web UI stays off.

### State

The agent home is backed by `/persist/home/slop-cannon`. It holds the provider logins and
sessions, repos, and `~/.paseo`, which contains the daemon keypair, agent records, projects,
workspaces and Paseo-managed Git worktrees. Paired clients trust that daemon keypair. Claude
sessions live under `~/.claude/projects/` and Codex sessions under `~/.codex/sessions/`.

## Repos, worktrees and jj

Repos live under `~/src` as colocated jj clones (see `slop-clone` below). The fork drives them
through `jj`:

- A `local` workspace runs the agent in the checkout itself. Archiving it removes only Paseo's
  record; the folder is kept.
- A new jj workspace is a colocated `jj workspace` under `~/.paseo/worktrees` with its own
  working-copy change. Use it for parallel or unattended agents. Archiving saves the change for
  restore before removing the directory.
- A workspace goes stale when another one rewrites its `@`, typically a `jj git fetch` after its
  pull request is merged. Paseo then offers **Update stale workspace** (`jj workspace
  update-stale`), which keeps edits jj hadn't recorded in a separate change. Run it once the
  workspace's agent is idle, since it changes the files under it.
- Don't run `jj` in a folder while an agent is mid-turn there: jj snapshots its partial edits.

## Terminal access

- The `paseo` CLI talks to the running daemon: `paseo ls`, `paseo logs -f <id>`, `paseo send <id>
  "…"`, `paseo permit ls|allow|deny`. It is command-line only, not a chat interface.
- A session can be taken over in the provider's own TUI by its ID: `claude --resume <session>` in
  the agent's folder, or `codex resume <session>`. `paseo import` goes the other way. This is a
  hand-off, not a shared view: stop the agent in Paseo first and don't type in both.

## Agent permissions

Paseo has the full rights of `slop-cannon`, and `slop-cannon` has root: anyone with the daemon
password or a pairing controls the VM.

- Claude Code and Codex come from the shared `my.agents` home-manager module.
- Claude's user settings deny raw `deploy` and `ssh-machine`, and allow `slop`, since the broker
  asks a human where its policy says so. The checkout's `.keys/` only has the committed public
  keys, so reading it isn't denied. Claude's managed settings
  (`/etc/claude-code/managed-settings.json`) repeat the `deny` rules. All of these match command
  text and live inside the guest, so they steer agents towards `slop` rather than enforce
  anything.
- Agents are permissive by default, since the VM is the boundary and
  [`slop-broker`](../../slop-broker.md) gates everything that needs credentials: Claude starts in
  `bypassPermissions` (the `deny` rules still apply), and Codex runs without approvals or its
  sandbox (`approval_policy = "never"`, `sandbox_mode = "danger-full-access"`). Agents started
  through Paseo use its defaults unless started with one of the profiles above.
- Codex stores its credentials in a file.

### Privileged operations

Agents ask [`slop-broker`](../../slop-broker.md) on `palace` for anything needing credentials, with
the `slop` command (`my.agents.slop.enable`). It connects over vsock (CID 3; see
[`palace`](palace.md#slop-broker)). The agent guide, `slop guide`, is installed as a Claude rule
(`~/.claude/rules/slop.md`) and as Codex's `AGENTS.md`.
The `my.agents.rules.slop-approvals` rule adds the local guidance on waiting for approval
and pausing after expiry to both providers' user-level instructions, including in Paseo sessions.

## SSH and first login

`ssh slop-cannon` (agent user) and `ssh slop-cannon-dev` (`dev`) are the shared aliases, both with
`ForwardAgent=no`. Never forward your SSH agent into the box: agents could use it while you're
logged in. For recovery, use the [VM serial console](../../deployment.md#vm-consoles) for
`slop-cannon` on `palace`.

To set up provider logins and repos on a fresh agent home, connect with `ssh slop-cannon`:

1. `claude auth login` (a full login; `setup-token` tokens are not enough for every feature).
2. `codex login --device-auth`.
3. [Pair a Paseo client](#pair-a-paseo-client).
4. `slop-clone <owner>/<repo>` for each repo. It clones a colocated jj repo over HTTPS into
   `~/src/<repo>` and registers it with Paseo as a local workspace.

## Gitea

Agents reach Gitea as a bot user, with its access token (age secret `slop-cannon/gitea-token`,
scopes `write:repository` and `write:issue`).

- **Git** uses HTTPS: a credential helper for `git.nul.ie` sends the token. Commits are still
  authored as Dev through the shared Git config; the pushes are the bot's.
- **`tea`**, Gitea's CLI, is wrapped to log in with the same token, so agents can open and update
  pull requests.
- **Pull requests:** a rule for every agent (`my.agents.rules.gitea`: a Claude rule, and part of
  Codex's `AGENTS.md`) makes a pull request from a branch of its own the default way to finish a
  piece of work, and says how with jj and `tea`. A repository's own `AGENTS.md` can allow more,
  such as pushing to its main branch.
- **Access per repo:** where agents should only propose changes (`dev/nixfiles`, `slop-broker`),
  protect the main branch so only Dev pushes and merges. Elsewhere the bot's Write access is
  enough to push directly.
- **Access:** the bot is a collaborator with Write on each repo agents may use. `master` on
  `dev/nixfiles` only takes pushes and merges from Dev (see
  [`slop-broker`](../../slop-broker.md#master-is-protected)).
- **Replacing the token:** make a new one for the bot and put it in the secret with
  `ragenix -e secrets/slop-cannon/gitea-token.age`, then deploy `slop-cannon`.

## Pair a Paseo client

1. On the VM, run `slop-pair` as `slop-cannon`. It prints the QR code, pairing link and
   `PASEO_PASSWORD`. Keep its output private.
2. If you only need the QR code and link, run `paseo daemon pair` as `slop-cannon`. To look up the
   password separately, run `doas cat /run/secrets/slop-cannon/paseo.env` on the VM. You can also
   decrypt it from a repo checkout with access to the dev age key:

   ```sh
   rage --decrypt -i .keys/dev.key secrets/slop-cannon/paseo.env.age
   ```

3. On a phone, scan the QR code from the Paseo app. In a browser, open `https://slop.nul.ie` and
   use the app's paste-pairing-link option. Enter the value after `PASEO_PASSWORD=` when prompted
   and open the paired host. If the browser shows “Password required” after opening the link in
   the address bar, remove that host entry and pair again using the paste dialog.

## Notable config files

- [`nixos/boxes/home/palace/vms/slop-cannon.nix`](../../../nixos/boxes/home/palace/vms/slop-cannon.nix) —
  the box: users, Paseo, Claude settings, `slop-clone`, `slop-pair`, disk layout, network.
- [`nixos/boxes/home/palace/slop-broker.nix`](../../../nixos/boxes/home/palace/slop-broker.nix) —
  the broker's policy for this box and the VM's vsock device.
- [`nixos/boxes/home/palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix) —
  the VM on `palace` and `slop-cannon-disk.service`.
- [`nixos/boxes/home/palace/default.nix`](../../../nixos/boxes/home/palace/default.nix) — VF 5, the
  NVMe host ID and the LVM filter.
- [`home-manager/modules/agents/default.nix`](../../../home-manager/modules/agents/default.nix) —
  shared Claude Code and Codex configuration, including the `slop` client and guide.
