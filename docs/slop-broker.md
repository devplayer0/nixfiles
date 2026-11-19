# slop-broker

`slop-broker` lets agents use credentials they must never hold: deploy and SSH keys, the age
identity for secrets, the binary cache and the Cloudflare API. It is built for the agents on
[`slop-cannon`](sites/home/slop-cannon.md), but agents elsewhere can use it too (see
[Other requesters](#other-requesters)). The broker runs on `palace`, outside the VM. Agents send
it requests through the `slop` CLI, and it carries out each one under a policy, usually after Dev
approves it from a terminal or the phone.

**Status:** in progress. The broker core, the box queries, `slop ssh` and the SSH transport are
done; the other operations here are planned (see [Implementation plan](#implementation-plan)).
The code is in [`pkgs/slop-broker`](../pkgs/slop-broker) (Rust), the service is
`my.slop-broker`, and `palace`'s configuration is
[`palace/slop-broker.nix`](../nixos/boxes/home/palace/slop-broker.nix).

## Trust model

- Everything inside `slop-cannon` is agent-controlled, including root, and so is any other
  requester. Anything a requester sends is untrusted: commands, file contents, commit IDs,
  labels and its own descriptions of requests.
- The broker holds the credentials and runs every privileged step itself. A credential never
  reaches a requester. The only exception is an explicit `slop secret read`.
- Each requester names a policy, and several requesters can share one. Leases and request
  limits are still counted per requester.
- Each request has a **scope**, which is what an approval covers (for example: deploy `sfh` at
  commit X). The broker builds both the scope and the text shown to the approver from validated
  fields, never from text the agent wrote.
- Anything returned to a requester should be treated as published. It ends up in the agent's
  context, so in the model provider's transcript and in the session logs under `~/.claude` and
  `~/.codex`.
- The broker evaluates and builds agent-written Nix only as a separate user without keys. Its
  privileged half only copies, signs, encrypts or activates the results.
- `palace` already hosts the VM and will hold the deploy key, which is root on every box. Also
  giving the broker access to every secret adds little exposure on top of that.

## Transport

- The VM gets a `vhost-vsock` device with a fixed CID. The broker listens on `AF_VSOCK` on
  `palace`, and the kernel-reported peer CID identifies the requester. Nothing the guest sends
  can change its CID.
- Messages are typed Rust enums shared by `slop` and the broker, encoded as CBOR and framed with
  a length prefix (`tokio-util`'s `LengthDelimitedCodec`). Decoding validates every value (node and
  unit names, ports and so on) and rejects unknown fields. The request carries a protocol version,
  so a mismatched `slop` gets a clear error.
- One connection carries the request, then the operation's stdin (only after approval, and only
  for operations that read it), its stdout and stderr, and a final message with the exit status
  and any structured result. If the connection closes, the broker cancels the request or kills the
  process it started.
- The VM never connects to the broker over the network. This keeps the `untrusted` VLAN filter on
  the routers unchanged.

### Other requesters and approvers

Requesters and approvers on other boxes connect with SSH instead of vsock. That reuses `sshd` for
authentication and stream handling.

- They log in as `slop` on `palace`. Each key has a forced command,
  `slop-broker remote <requester|approver> <name>`, set from `requesters.<name>.sshKeys` or
  `sshApprovers.<name>`. It connects to the broker's remote socket, which only `slop` can use, and
  tells the broker whose key it is. The broker trusts that the same way it trusts a CID.
- A key does one job. The module refuses the same key as both requester and approver, and the
  client says which job it wants (`ssh … request` or `ssh … approve`), so a key used with the
  wrong client fails with a clear error.
- A requester key only allows making requests, so it's fine for the agents on that box to be able
  to read it. An approver key must be out of their reach.
- Each requester names a policy. `slop-cannon` is identified by its CID, the others by their
  key. For example, workstations might share a policy that only allows `dns`, the box queries
  and `requests`.
- `slop` connects to `$SLOP_BROKER`, else `broker` in `~/.config/slop/config.toml`, else vsock;
  `slop-approve` likewise uses `$SLOP_APPROVE`, else `approve`, else `approve.sock` on the box.
  An `ssh:<destination>` address goes to `ssh` as is, so a `Host` entry with `IdentitiesOnly` can
  pick the right key when a box has both kinds. `SLOP_SSH` replaces the `ssh` command, like
  `GIT_SSH_COMMAND`.
- The `my.slop` home-manager module sets this up: `my.slop.request` and `my.slop.approve` each take
  a key file, and get the `slop-request` and `slop-approve` `Host` entries and the config file
  pointing at them. A config file rather than session variables, because shells started before a
  switch don't see new variables.
- The nixfiles devshell has `slop` and `slop-approve` too, built from the checkout so they match
  the branch. Its `slop` uses `.keys/slop-request.key` over SSH when that file exists, so a
  checkout without the other keys only needs that one; otherwise it behaves like the installed
  client. An approver key never goes in `.keys/`: agents can read the checkout.

## The `slop` CLI

There is one client command. Every subcommand blocks until the request is answered,
then streams the output.

| Command | Purpose | Default policy |
|---|---|---|
| `slop status <node> [unit]`, `slop logs <node> <unit>`, `slop failed <node>` | Fixed read-only queries on boxes | auto |
| `slop ssh <node> -- <cmd>`, `slop ssh --host user@host[:port] -- <cmd>` | Any command over SSH | ask |
| `slop deploy <node>… --commit <id> [--boot]` | Build an approved commit and deploy it | ask |
| `slop build <attr>… --commit <id>` | Build on `palace` and push to the main binary cache | ask |
| `slop secret keys\|set\|generate\|rekey\|read …` | Work with age secrets | `keys` auto, `read` always ask, others ask |
| `slop dns list\|set\|delete …` | Change records in the public Cloudflare zones | `list` auto, others ask |
| `slop preview <port> [--name n] [--public] [--auth basic\|sso] [--ttl 4h]` | Publish a dev server on `*.slop.nul.ie` | ask |
| `slop requests` | Show this requester's pending requests and active leases | always allowed |

Every request can carry `--label` (agent, repo and a one-line reason). The CLI fills it in
automatically where it can. Approvals show it marked as agent-supplied.

## Approvals and policy

- Each operation has a policy, configured in Nix: `auto`, `ask` or `deny`, plus the lease lengths
  it allows (`"5m"`, `"1h"`). The module writes the broker's configuration as TOML. Narrower rules override wider ones, for example per node, per DNS name or per
  secret path.
- Policies are named in `my.slop-broker.policies`, and each requester picks one with `policy`,
  so several requesters, for example agents on different boxes, can share the same rules.
- An `ask` request waits up to five minutes for an answer from `slop-approve` (on `palace`, or
  over SSH from another box) or a Home Assistant Companion notification. The answers are **once**, a **lease** (the same scope
  is approved for a while, for example 5 min or 1 h, and only lengths the policy allows are
  offered) or **deny**.
- `auto` operations are rate-limited per requester, so a looping agent can't hammer boxes or APIs.
- Pending requests are capped per requester and overall to limit notification spam. If the broker
  restarts, pending requests and leases are dropped.

### Home Assistant notifications

The broker keeps an outbound connection to Home Assistant's
[WebSocket API](https://developers.home-assistant.io/docs/api/websocket/) and sends a
[Companion actionable notification](https://companion.home-assistant.io/docs/notifications/actionable-notifications/)
for each `ask` request.

- The notification text is built from the scope, followed by the agent's label. Requests that
  reveal a secret or change recipients are marked.
- Notifications are sticky and persistent: tapping one doesn't remove it, and before Android 14 it
  can't be swiped away either. The broker clears each one once its request is answered, expires or
  is cancelled. Since Android 14, users can dismiss even persistent notifications, and apps can't
  prevent it. A dismissed request stays pending until it's answered elsewhere or expires.
- A possible fix: the Companion app fires `mobile_app_notification_cleared` when a notification is
  dismissed. The broker could watch for it and re-post the notification while its request is still
  pending, on a quiet notification channel so it doesn't alert again. Check first that the event
  carries the notification's `tag`. The approvals web app (below) would make this matter less.
- Action IDs are random and never shown to the VM. A reply must match a live action and the
  configured `device_id`: the Companion app's own ID, which differs from the device registry's.
  The broker logs the ID of any answer it ignores, which is how to find it. Home Assistant, and
  anyone who can fire events on it, is trusted to approve.
- If the connection fails, requests stay pending; a failure never approves anything. When the
  broker reconnects, it reissues pending notifications with new action IDs.

### Audit log

Each request, decision, approver, lease use and result is an event with the request's ID. The
broker writes it to the journal as a line of text and to `/var/lib/slop-broker/audit.jsonl` as a
line of JSON. `slop-approve log [-n 50] [--json]` shows the recent events through the approve
socket, with each request's full detail. Secret operations record the file and a hash of the
ciphertext before and after, never values.

## Operations

### Box queries and SSH

- Targets are deploy-rs nodes, taken from trusted config. `--host` covers boxes outside the flake
  (OpenWrt, switches) with an explicit `user@host` and port.
- SSH runs with options fixed by the broker: `-F none`, the key with `IdentitiesOnly`, no agent,
  `BatchMode`, no forwarding or local commands, and the broker's own `known_hosts`.
- `ssh` joins its arguments into a string that the remote shell runs. Because of that, a
  free-form command's text can't be judged as read-only, so `slop ssh` is always `ask`.
- The fixed queries (`status`, `logs`, `failed`) validate their arguments (unit names, `--since`,
  line counts), and the broker builds the quoted remote command. That makes them safe to run as
  `auto`, which covers most of what agents need SSH for without prompting.

### Deploys

1. The agent pushes its commit to Gitea, then runs `slop deploy <node> --commit <id>`.
2. The broker fetches that commit from `git.nul.ie`, not from the VM. It evaluates and builds it
   as `slop-broker-build`, a user without keys, using `palace`'s Nix daemon with the main cache as
   substituter. Building runs nothing privileged, so it happens **before** approval, rate-limited
   per requester.
3. The broker copies the node's current system closure from the node, a fixed read-only step that
   runs no agent-written code. It then compares it with the new one.
4. One approval shows the commit, the closure diff and the changed units (see the example below).
5. Once approved, the privileged half runs deploy-rs on the built profile with the deploy key and
   streams the output back to the agent.

Activation, including `dry-activate`, runs agent-written code as root on the node. So nothing is
activated before approval.

Paths built this way come from the daemon's sandboxed builds, so they can be pushed to the main
cache. That's also what `slop build` does without deploying.

#### Approval contents

The closure diff comes from [`nvd`](https://khumba.net/projects/nvd/) and shows package versions,
not configuration. The broker adds a configuration summary by comparing the two systems' `etc`
trees: which systemd units and `/etc` files changed. That approximates what activation will
restart, without running anything. The full view, in `slop-approve show <id>`, looks like this:

```text
deploy sfh  (switch)
Commit 3f9c2e1…  by agent "hass-upgrade" on slop-cannon (agent-supplied)
  3f9c2e1 nixos/sfh: Update Home Assistant
  8a1b7d0 nixos/hass: Add Zigbee coordinator
  nixos/boxes/home/sfh/containers/hass.nix | 14 +++++++++-----

Packages (nvd):
  [U.]  home-assistant         2026.11.1 -> 2026.11.2
  [U.]  python3.13-zha         0.0.71 -> 0.0.72
  [A.]  python3.13-bellows     0.46.1
  Closure: 4211 -> 4219 paths, +38.2 MiB

Configuration:
  changed units:  container@hass.service, home-assistant.service (in hass)
  changed files:  /etc/hass/configuration.yaml (in hass)
  added units:    -
  removed units:  -
```

The phone notification carries the first line, the counts (commits, package changes, changed
units) and the label. It isn't the place to review a large deploy. For those, approve from a
terminal.

### Binary cache

Anything in the Harmonia store is signed and trusted by every box. A path built inside the VM
proves nothing, because the agent could upload a different output under the hash of a real
derivation. So:

- **Main cache:** filled only from builds done by `palace`'s daemon (`slop build`, deploys), using
  the existing Harmonia push key.
- **VM-built paths (optional, later):** a separate store with its own signing key, trusted only by
  `slop-cannon` and by boxes that opt in. Useful for sharing agent build artifacts or keeping them
  across VM rebuilds.

### Secrets

The broker has its own age identity. Its public key joins `.keys/dev.pub` in the recipients that
`secrets.nix` generates, so the dev key never goes to `palace`. Adding it needs one full rekey.

The agent sends the current `.age` file with each request, and the broker returns new ciphertext.
The broker never writes to a checkout.

| Command | Result | Value enters VM? |
|---|---|---|
| `keys <file>` | Key names of an env, JSON or YAML secret | No |
| `set <file> <key>` (value on stdin) | That field replaced, re-encrypted | Only what the agent sent |
| `set <file> --whole` | Whole file replaced | Only what the agent sent |
| `generate <file> <key> --type password\|hex\|base64\|wireguard\|ssh-ed25519\|age` | Value created by the broker; keypair types return the public half | No |
| `rekey <file> -r <recipient>…` | Re-encrypted to the given recipients | No |
| `read <file>` | Plaintext | Yes, so always `ask`, never leased |

- The VM lists the recipients. The broker names each one from the host keys and `dev.pub` on
  `master`, and shows changes from the file's current recipients. An unknown key is flagged in the
  approval. This avoids evaluating agent-written Nix just to get a recipient list.
- Encrypting to new recipients is done offline (`rage -r`) and needs no broker.
- The same operations work for any repository that uses age files with the broker as a recipient,
  not just this flake.

### DNS

The public zones (`nul.ie` and others) live in Cloudflare and are edited by hand. Internal zones
come from Nix config, so agents change those with commits and deploys instead.

- `slop dns list <zone> [name]` shows the live records. `slop dns set <name> <type> <value>…
  [--ttl] [--proxied]` replaces the record set for that name and type, and `slop dns delete <name>
  <type>` removes it.
- The approval shows the record set before and after, read live from Cloudflare. Leases are
  scoped by name and type.
- The broker uses its own Cloudflare API token, limited to DNS edits in the allowed zones. It's
  separate from the ACME and `ddclient` tokens.
- Policy denies zone apexes, `NS`, `MX` and `_acme-challenge` names by default. Records the broker
  creates get a Cloudflare record comment, so the approval can say whether an agent is changing
  one of its own records or an existing one.

### Previews

`slop preview 5173 [--name foo] [--public] [--auth basic|sso] [--ttl 4h]` publishes a dev server
in the VM until its TTL expires.

- `middleman` serves `*.slop.nul.ie` with a wildcard certificate and proxies to the broker on
  `palace`. The broker looks up the host in its active previews and connects to the guest port
  over vsock. The VM still accepts no inbound connections.

#### Access

The hostname and the authentication are chosen separately.

- **Secret URL (default):** the hostname is an unguessable label, for example
  `foo-<26 base32 characters>.slop.nul.ie`, which is 128 random bits after the optional name.
  Because DNS and the certificate are wildcards, the name never appears in the zone or in
  Certificate Transparency logs. Unknown hostnames get the same 404 as expired ones. Responses
  carry `Referrer-Policy: no-referrer` and `X-Robots-Tag: noindex`.
- **`--public`:** the hostname is just the name (`foo.slop.nul.ie`). Without `--auth` this is a
  fully public site. Public names are never leased, so each one needs its own approval.
- **`--auth basic`:** adds basic auth with a generated password. It's shown in the approval and
  returned to the agent, which needs it to test the page and controls the content anyway.
- **`--auth sso`:** adds the existing `nginx-sso` login on `middleman` (`sso.nul.ie`).
- The secret URL still leaks through browser history, shared links and resolver logs. Use an auth
  option for anything that matters.
- **Accepted risk:** `*.slop.nul.ie` is same-site with every other `nul.ie` service. A preview page
  can set cookies on `.nul.ie`, and browsers send `SameSite=Lax` cookies (including the SSO
  session) with its requests to other `nul.ie` services. A separate domain would avoid this. We
  keep `nul.ie` for simplicity.

### TCP forwards (later)

Time-limited access from the VM to one internal `host:port` (for example a database), approved
per destination. This waits until a concrete need comes up.

## `slop.nul.ie`

`slop.nul.ie` replaces `paseo.nul.ie` for the Paseo web app on `middleman` (`paseoWebUi` in
`vhosts.nix`, `app.baseUrl` in `slop-cannon.nix`), and `*.slop.nul.ie` is used for previews. The
relay stays on `paseo-relay.nul.ie` for now, because existing pairings use that hostname.

## Agent-facing docs

- **Agent context:** the package ships
  [`slop-tools.md`](../pkgs/slop-broker/slop-tools.md), which describes the `slop` CLI and how
  requests behave (they block while waiting for approval, so no retrying in a loop). With
  `my.agents.slop.enable`, the shared `my.agents` home-manager module installs `slop` and adds the
  guide as a Claude rule (`~/.claude/rules/slop.md`) and as Codex's `AGENTS.md`, so every project
  gets it. `slop guide` prints the same text. Update the guide with each new operation. The guide
  asks agents to suggest new operations when they would otherwise work around a missing one or
  keep asking for the same `slop ssh` approval.
- **Claude permissions:** the broker is the gate, so a Claude prompt would only ask twice.
  `slop-cannon` allows `Bash(slop:*)` and keeps the `deny` rules for raw `deploy`, `ssh-machine` and
  `.keys/`.
- **Other requesters** get the same `slop-tools.md` through the shared `my.agents` home-manager
  module, limited to the operations their policy allows.
- **`AGENTS.md`:** a short "Working from `slop-cannon`" rule pointing at `slop` instead of
  `deploy`, `ssh-machine` (and later `ragenix`), linking this page. Extend it as operations land.
- **Box pages:** `slop-cannon.md` (agent permissions, SSH and deploys) and `palace.md` (the broker
  service and its vsock device) summarize and link here.

## Implementation plan

Each step updates this page, the agent context and the box pages as it lands.

1. **Done — `slop.nul.ie`:** move the web app and add the wildcard name to the certificate. This
   doesn't depend on the broker.
2. **Done — core, in Rust** (replacing the Python prototype): vsock transport, typed and versioned
   messages, an operation registry (parse, scope, describe, execute, policy), the `slop` CLI, the
   audit log, and the existing SSH and Home Assistant support ported over. Run it on `palace` with
   the VM's CID.
3. **Done — box queries** as `auto` operations.
4. **Done — SSH transport** for requesters and approvers on other boxes.
5. **Deploy executor and `slop build`:** fetch from Gitea, build as `slop-broker-build`, push to
   the main cache, run deploy-rs.
6. **Secrets:** the broker's age identity, a one-off rekey, then the operations.
7. **DNS**, with its Cloudflare token.
8. **Previews.**
9. **TCP forwards and the VM-built cache**, if needed.

## Scope

- **Out of scope for now:** secret tools other than age (such as `sops`), and a general
  credential proxy for other APIs (forges, package registries). Agents keep using Gitea deploy
  keys for pushing. If more API operations are needed later, add them one at a time like `dns`.

## Tests

- **Unit and integration tests** cover the protocol, policy, approvals, leases and SSH execution
  against a fake `ssh`. They run in the package build, or by hand:

  ```sh
  cd pkgs/slop-broker && nix shell pkgs#cargo pkgs#rustc pkgs#gcc -c cargo test
  ```

- **VM test** ([`vm-test.nix`](../pkgs/slop-broker/vm-test.nix)): a minimal system running the
  broker through the `my.slop-broker` module, with its real service hardening, over vsock
  loopback, against a local `sshd`. Run it after changing the module, the service or the
  transport:

  ```sh
  nix build -L .#slop-broker.tests.vm
  ```

- New operations add tests against fakes of what they call (deploy-rs, the Cloudflare API).
