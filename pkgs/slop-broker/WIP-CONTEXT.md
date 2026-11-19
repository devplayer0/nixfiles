# slop-broker: working context (WIP, not for merge)

Working notes for whoever picks up `slop-broker` next. They describe how the core is built, how to
add an operation, and where the work stands. They live in their own change at the top of the stack
and are not meant to land as they are. When the work is done, move the durable parts (architecture,
how to add an operation) into [`docs/slop-broker.md`](../../docs/slop-broker.md) and drop this file.

The design and plan are in [`docs/slop-broker.md`](../../docs/slop-broker.md); this file doesn't
repeat them.

## Progress

As of 2026-11-20. The jj stack, oldest first, on top of `master`. Generic code (package, modules,
docs) comes first and box config last, so each box change can be reviewed and deployed as a unit.
The `slop-broker` bookmark on Gitea is a branch for testing on `slop-cannon`; no PR is open.

| Change | State |
|---|---|
| `AGENTS.md: Spell out blank lines inside functions` | Done; unrelated to the broker, but sits at the bottom. |
| `nixos/middleman: Move Paseo web app to slop.nul.ie` | Done. `slop.nul.ie` and `*.slop.nul.ie` are CNAMEs to `http.int.nul.ie` in Cloudflare, and the certificate covers the wildcard. |
| `pkgs/slop-broker: Add approval broker for coding agents` | Done: Rust core, `slop ssh`, `my.slop-broker`, `my.agents.slop`, agent guide, VM test, Home Assistant support, named policies, TOML config, typed audit log, `slop-approve log`. |
| `pkgs/slop-broker: Add box queries` | Done: `status` / `logs` / `failed`. |
| `pkgs/slop-broker: Add SSH transport` | Done: requesters and approvers on other boxes, the client config file, the `my.slop` home-manager module, devshell `slop` / `slop-approve`. |
| `pkgs/slop-broker: Add deploys` | Done: `slop deploy`, the builder (`slop-broker builder`, `my.slop-broker-builder`), comparison on nodes, parallel activation. Tested end to end (`slop deploy slop-cannon --boot`). |
| `nixos/palace: Run slop-broker for slop-cannon's agents` | Deployed. |
| `nixos/castle: Use slop-broker over SSH` | Switched on `castle`. |
| `nixos/palace: Shrink slop-cannon to 24 GiB` | Deployed and in effect. |
| `nixos/palace: Let agents deploy through slop-broker` | Deployed; Gitea has the builder's read-only deploy key. |
| `nixos/palace: Send slop-broker approvals to Home Assistant` | Deployed and tested (a tap on Once approves). |
| `WIP: slop-broker context notes (not for merge)` | This file. Keep it at the top of the stack. |

`palace` runs the tip of the stack (below this change) and `castle` is switched to it.
`slop-cannon` booted the configuration from its own `--boot` test deploy, which predates the
latest client changes; redeploy it to pick them up.

Next, in order: `slop build` (needs a new SSH key for the `harmonia` user on `object`, held by the
broker only), then the approvals web app's design (see the section in `docs/slop-broker.md`; Dev
wants passkeys explained in more depth and push options explored), then secrets (step 6, with a
full rekey).

Workspaces: this one (`nixfiles-jj3`, with `.keys/`), `../nixfiles-deploy-broker` (no private
keys, for trying `slop` as an agent would) and `default` (`../nixfiles-jj`).

## Architecture

### Layout

| File | Responsibility |
|---|---|
| `src/proto.rs` | Messages (`ClientMessage`, `ServerMessage`, `Operation`, `OpResult`, approver messages), framing and encoding |
| `src/types.rs` | Validated value types (`NodeName`, `UnitName`, `Since`, `Lines`, …) used inside messages |
| `src/config.rs` | TOML config from the NixOS module (durations as `"5m"`); credential path, user and group lookups |
| `src/policy.rs` | `auto` / `ask` / `deny` evaluation, rules with globs, per-operation `Limits` |
| `src/queue.rs` | Pending approvals, decisions, leases, per-requester limits and rate limits |
| `src/server.rs` | Listeners (vsock, Unix), the per-connection handler, `authorize` |
| `src/exec.rs` | Running processes on the requester's framed stdio; cancellation |
| `src/ops/mod.rs` | `plan` (request → `Parsed`: scope, approval text), `execute`, quoting |
| `src/ops/ssh.rs`, `src/ops/query.rs`, `src/ops/deploy.rs` | Operations; `deploy.rs` also has the `INSPECT` comparison script and its parser |
| `src/builder.rs` | Both sides of the builder: the worker (forced command) and the broker's client |
| `src/approve.rs` | Approver connections (many requests each), `slop-approve` client, `approve()` used by every approver |
| `src/remote.rs` | SSH transport: the `slop-broker remote` forced command, the remote socket, `connect` for both clients, and `address` (environment, then `~/.config/slop/config.toml`, then the default) |
| `src/ha.rs` | Home Assistant Companion notifications |
| `src/audit.rs` | Typed audit events: a text line to the journal, a JSON line to the file; `tail` for `slop-approve log` |
| `src/bin/slop-broker.rs` | Daemon (`serve`); `slop-approve` when run under that name |
| `src/bin/slop.rs` | Agent client; `slop guide` prints `slop-tools.md` |
| `tests/broker.rs` | Handler tests over an in-memory duplex stream with a fake `ssh` |
| `vm-test.nix` | NixOS VM test: a minimal system using the `my.slop-broker` module (`slop-broker.tests.vm`) |

### Request lifecycle

1. A listener accepts a connection and maps it to a requester name: vsock by peer CID, the Unix
   request socket by peer UID, the remote socket by the `Hello` its forced command sends. Anything
   unknown is refused and logged.
2. `server::handle` reads one `ClientMessage::Request` (10-second limit), then starts a reader task
   that forwards `Stdin` to a channel (closing it at `StdinEnd`) and cancels a `CancellationToken`
   when the connection closes or misbehaves. A writer task sends every `ServerMessage` from an
   `mpsc` channel, in order.
3. The protocol version is checked. `ops::plan` checks the already-typed `Operation` against config
   (does the node exist?) and returns `Parsed`: the scope, what approvers are shown, limits, whether
   stdin is used, and the operation. For a deploy, a policy pre-check (deny stops here) and
   `ops::prepare` follow: build, copy, compare, and fill in the detail (`Event::Prepared`).
4. `authorize` evaluates policy for the requester and operation. `deny` refuses. `auto` takes a
   rate-limit slot. `ask` uses a matching lease if there is one, otherwise submits to the queue,
   sends `Pending`, and waits for a decision, the timeout or a disconnect.
5. The handler sends `Approved { by, stdin }`. The client starts forwarding stdin only then, and
   only if `stdin` is set.
6. `ops::execute` runs the operation with `Io` (stdin channel, output sender, cancel token) and
   returns an exit status and an optional `OpResult`.
7. The handler sends one terminal message (`Finished`, `Denied`, `Expired`, `Error`), or nothing if
   the requester went away, then closes.

Every step is audited as an `audit::Event` carrying the request's ID (the same ID approvers see):
`request`, `prepared`, `approved` (with the approver's name), `decision`, `denied`, `expired`,
`finished`, `failed`, `disconnected`, plus `invalid` and `unknown` peers. Built-in operations (`requests`) aren't logged.

### Protocol

- Each message is a serde enum from `src/proto.rs`, encoded as CBOR (`ciborium`; byte strings via
  `serde_bytes`) and framed by `LengthDelimitedCodec` (4-byte big-endian length, 1 MiB maximum).
- Requester → broker: `Request { version, label, operation }`, then `Stdin(bytes)` / `StdinEnd`.
- Broker → requester: `Pending`, `Approved { by, stdin }`, `Info`, `Stdout`, `Stderr`, then one of
  `Finished { exit, result }`, `Denied`, `Expired` or `Error`.
- Every enum and struct has `deny_unknown_fields`, and value types validate in `TryFrom`, so a
  request that decodes is well-formed. `plan` only checks it against config.
- Bump `PROTOCOL_VERSION` on any incompatible change: `palace` and `slop-cannon` are deployed
  separately.
- Approver connections use the same framing with `ApproveRequest` / `ApproveResponse`, any number
  per connection.
- The remote socket starts with a `remote::Hello { role, name }`, written as one length-prefixed
  frame without the codec so nothing after it is read ahead, then carries either protocol.
- The builder gets one `BuildRequest` frame on stdin and answers with one `BuildResult` frame on
  stdout; build logs go to stderr, which the broker forwards to the requester.
- `slop` exits with the operation's status for `Finished` and 125 for anything else. `--json`
  prints an `OpResult` as JSON.

### Policy, leases and limits

- Config: named `policies.<name> = { max_pending, auto_per_minute, ops.<op> = { action, leases,
  rules } }`, and `requesters.<name>.policy` picks one, so requesters can share a policy.
  `Config::validate` (called by `Broker::new`) refuses a requester whose policy is missing, and the
  module asserts the same. A missing operation is denied.
- Rules match scope fields with globs (`*`, `?`); the first match wins and can replace `leases`.
- An operation's `Limits` override policy: `never_auto` turns `auto` into `ask`, and `never_lease`
  removes leases (for example, `secret read`).
- The lease key is the operation name plus the scope's canonical JSON (serde_json maps are sorted),
  per requester. The command is in the detail, not the scope, so a lease covers any command to the
  same target.
- Approvers are offered `once`, each allowed lease (`5m`, `1h`, …) and `deny`. A lease that wasn't
  offered is refused.
- Limits: pending requests per requester and overall, and `auto` requests per minute per
  requester. A shared policy shares the numbers, not the counters or leases. Everything is in memory; a restart drops pending requests and leases.

### Execution

`exec::run` starts the process in its own process group, pumps stdout and stderr into frames, and
feeds stdin from the channel. On cancellation it sends `SIGTERM` to the group, then `SIGKILL` after
five seconds. It retries a spawn that fails with `ETXTBSY`, which happens when another thread forks
while an executable is still open for writing (seen in parallel tests). `exec::capture` runs a
process without the requester's stdio, for broker-internal steps. `exec::run_prefixed` runs one
without stdin and sends each output line with a prefix, so several nodes can share the output
(deploy copies and activations).

SSH always uses options fixed in `ssh::command`: `-F none`, the credential key, no agent,
`BatchMode`, no forwarding, its own `known_hosts` (`accept-new`), and `--` before the hostname.
Arguments from the requester are validated so none can be read as an option.

### Approvers

- `approve.sock` is restricted to the `slop-broker-approve` group. A requester's UID is refused
  even if it is in the group. The approver is recorded by user name.
- Over SSH, approvers are named in `sshApprovers` and recorded as `<name> (ssh)`.
- Home Assistant: an outbound WebSocket connection. Each pending request becomes a persistent,
  sticky notification with random action IDs for Once, the shortest lease and Deny (Android shows
  at most three). Replies must match a live action and the configured `device_id`, which is the
  Companion app's own ID (the broker logs the ID of answers it ignores). It resyncs whenever the
  queue changes (`Queue::subscribe`) and every five seconds, and logs why a connection failed.
- All of them call `approve::approve`, which records the decision and audits it; the approver's
  name travels with the outcome into the `approved` event.

### NixOS side

- `nixos/modules/slop-broker.nix` turns options into the TOML config (`pkgs.formats.toml`, nulls
  dropped). Credentials arrive through
  `LoadCredential` under fixed names (`ssh-key`, `ha-token`), which `config::credential` resolves in
  `$CREDENTIALS_DIRECTORY`. SSH targets default to every deploy-rs node.
- The service runs as `slop-broker` with a strict systemd sandbox. Each operation that needs more
  (address families, writable paths, helper users) adds it in the module, and the VM test should be
  rerun.
- `palace/slop-broker.nix` holds the `agent` policy, the `slop-cannon` (CID 3) and `castle` requesters
  that use it, the deploy-key
  secret and the VM's `vhost-vsock-pci` device.
- Remote keys become `authorized_keys` entries for the `slop` user with a forced
  `slop-broker remote <role> <name>`; the broker gets `slop`'s group to share the remote socket.
- Agents get the client and guide from `my.agents.slop.enable` (home-manager). On other boxes,
  the `my.slop` home-manager module installs both clients and sets up `request` and `approve`
  keys: `Host` entries `slop-request` / `slop-approve` and `~/.config/slop/config.toml` pointing
  at them. The devshell's `slop` uses `.keys/slop-request.key` when present.
- `castle` is set up as both requester and approver (`~/.ssh/slop-castle-request`,
  `~/.ssh/slop-castle-approve`).
- Deploys: `my.slop-broker.deploy` (broker side) and `my.slop-broker-builder` (the
  `slop-broker-build` user, its read-only Git key and forced command). On `palace` the broker
  reaches the builder over SSH to localhost with the deploy key.
- Home Assistant: `ws://` to `hass`'s IPv4 address (`allAssignments.hass.hi`), because the
  `slop-broker` user there is local-only and Home Assistant counts the public IPv6 addresses as
  remote. The user must be an admin: non-admins can't subscribe to notification actions.

## Adding an operation

1. Add the `Operation` variant in `src/proto.rs`, using validated types from `src/types.rs` (add new
   ones there), and an `OpResult` variant if it returns data. Bump `PROTOCOL_VERSION` if old clients
   would misread anything.
2. `src/ops/<op>.rs` and a `plan` arm in `src/ops/mod.rs`: the config checks, a scope that is
   exactly what an approval should cover, and an `execute` arm.
   - Put anything shown but not part of the approval (commands, diffs) in `detail`.
   - Set `limits` and `sensitive` where the operation reveals or redistributes secrets.
3. Add the client subcommand in `src/bin/slop.rs` (clap parses validated types directly through
   `FromStr`), and how to print its `OpResult`.
4. Tests: parsing in the module, behaviour in `tests/broker.rs` with fakes of what it calls.
5. Module options and sandbox changes. The policy entry in `palace/slop-broker.nix` goes in a
   separate `nixos/palace` change after the generic one.
6. Agent guide (`slop-tools.md`), the `AGENTS.md` section, `docs/slop-broker.md` and box pages.

## Conventions and gotchas

- Run `cargo fmt` (`rustfmt.toml`: width 120) and `cargo clippy --all-targets`; keep both clean.
- Report errors to requesters with `{error:#}` so the cause chain is included.
- Messages to requesters are read by agents. Make them say what to do instead (for example
  "use --host for other boxes").
- Remote login shells are usually `fish`. Commands the broker builds are one `shell_quote`d string,
  which both POSIX shells and `fish` read the same way as long as the words contain no `\\` or `\'`.
- Unix socket paths are limited to about 108 bytes, so the scratchpad is too deep for manual tests;
  use a short directory under `/tmp/claude-1000`.
- `cargo build` leaves `target/` in the package directory. It is ignored, but if jj snapshots it
  before the ignore rule applies, run `jj file untrack pkgs/slop-broker/target`.
- Claude Code's default Bash timeout is two minutes, shorter than the approval timeout; the agent
  guide tells agents to use a longer timeout or run `slop` in the background.
- tokio's `Command::output()` captures stdout and stderr whatever they're set to; to let a child's
  stderr through, `spawn()` and `wait_with_output()`.
- ssh keeps the first value of an option. `nix copy` to `ssh://` adds `PermitLocalCommand=yes` and
  waits for `echo started`, so the broker's `PermitLocalCommand=no` would hang it forever (see
  `copy_options`).
- A tokio program that reads stdin can't return from `main` while that read blocks; the builder
  worker calls `std::process::exit` after writing its result.
- Session variables from home-manager only reach shells started after the next login
  (`__HM_SESS_VARS_SOURCED` is inherited), which is why `my.slop` writes a config file instead.
- jj doesn't create local bookmarks for new remote branches: after `jj git fetch`, use
  `jj new slop-broker@origin` or `jj bookmark track slop-broker@origin`.
- Changes that touch several stack changes at once (such as spacing sweeps) can be made at the tip
  and moved with `jj absorb`; it leaves lines whose neighbours come from different changes, which go
  into the later of the two.
- Claude Code's permission check refuses using the broker's deploy key directly (for example to
  test a command by hand on `palace`); test through the broker, or ask Dev.

## Not yet done outside the plan

- Home Assistant notifications can be swiped away on Android 14 and later (the phone runs 15);
  `persistent` no longer prevents it. The possible fix (re-post on
  `mobile_app_notification_cleared`, on a quiet channel) is described in `docs/slop-broker.md`;
  Dev chose to leave it for now.
- `slop-cannon` should be redeployed so its installed `slop` matches the branch.
- `vm-test.nix` needs KVM, so CI doesn't build it; run `nix build -L .#slop-broker.tests.vm`. It
  doesn't cover deploys or Home Assistant.
