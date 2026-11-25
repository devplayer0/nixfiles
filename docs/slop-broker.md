# slop-broker

[`slop-broker`](https://git.nul.ie/dev/slop-broker) carries out privileged operations (SSH
commands, deploys, builds and age secrets, and later DNS and previews) for the coding agents on
[`slop-cannon`](sites/home/slop-cannon.md) and other boxes, under a policy and usually after Dev
approves each one. Agents use the `slop` CLI.

The broker, its NixOS and home-manager modules, its design and the agents' guide live in its own
repository, which this flake takes as the `slop-broker` input. This page covers how these boxes use
it; for how it works, read the repository's
[design](https://git.nul.ie/dev/slop-broker/src/branch/main/docs/design.md).

## Boxes

| Box | Role |
|---|---|
| [`palace`](sites/home/palace.md) | Runs the broker, its builder and the approvals web app's listener; holds the deploy key |
| [`slop-cannon`](sites/home/slop-cannon.md) | The agents' VM; reaches the broker over vsock |
| [`castle`](sites/home/castle.md) | Agents there are a requester over SSH; Dev also approves from it over SSH |
| [`object`](sites/colony/shill/containers/object.md) | The binary cache that `slop build` pushes to |
| [`middleman`](sites/colony/shill/containers/middleman.md) | Publishes the approvals web app at `approve.slop.nul.ie`, Pocket ID at `id.nul.ie` and Paseo's web app at `slop.nul.ie` |

`palace`'s configuration is [`palace/slop-broker.nix`](../nixos/boxes/home/palace/slop-broker.nix):
the requesters, the `agent` policy they share, the secrets, and the web app settings. Its SSH
targets are the deploy-rs nodes on `master`, which the builder reads there, so a new box is a
target once it's merged.

### Updating the broker

- **Deploying `palace` doesn't restart the broker** (`restartIfChanged = false`), so it can see a
  deploy of its own box through. Afterwards, restart it for a new version or configuration to take
  effect: `doas systemctl --no-block restart slop-broker` on `palace`. A restart drops pending
  requests and leases.
- **Deploy every requester with it** when `slop`'s protocol version changes, or their requests fail
  with a protocol version error: `slop-cannon`, and `castle` over SSH.

## In this flake

- **Input:** `slop-broker` in [`flake.nix`](../flake.nix). Its overlay provides `pkgs.slop-broker`,
  and the common modules import `services.slop-broker`, `services.slop-broker-builder`,
  `services.slop-broker-cache` and `programs.slop`. Update it with `nix flake update slop-broker`.
- **Persistence:** [`tmproot.nix`](../nixos/modules/tmproot.nix) keeps `/var/lib/slop-broker` and
  the builder's home when those services are enabled.
- **Firewall:** the web app's port is open only to `middleman`, in `palace`'s configuration.
- **Agents:** `my.agents.slop` (in the shared `agents` home-manager module) installs `slop` and adds
  the guide (`share/slop-broker/slop-tools.md`) as a Claude rule (`~/.claude/rules/slop.md`) and
  as Codex's `AGENTS.md`. `slop-cannon` enables it, allows `Bash(slop:*)` in Claude and keeps the
  `deny` rules for raw `deploy` and `ssh-machine`.
- **`AGENTS.md`:** "Working from `slop-cannon`" points agents at `slop` instead of `deploy` and
  `ssh-machine`. Extend it as operations land.
- **Devshell:** `slop` and `slop-approve`, built from the locked input. `slop` uses
  `.keys/slop-request.key` over SSH when that file exists; an approver key never goes in `.keys/`,
  because agents can read the checkout.

## Other requesters and approvers

`castle` uses [`programs.slop`](https://git.nul.ie/dev/slop-broker/src/branch/main/docs/design.md#other-requesters-and-approvers):
its agents are the requester `castle` (same policy as `slop-cannon`), and Dev's approver key is
`sshApprovers.castle`. Both log in to `palace` as `slop`.

## Binary cache

`slop build` pushes into Harmonia's store on `object` as `harmonia`, whose broker key is limited to
the store protocol and GC roots (`services.slop-broker-cache` in `object`'s configuration). CI
collects garbage in that store on every run, which the roots survive until they expire (see the
[design](https://git.nul.ie/dev/slop-broker/src/branch/main/docs/design.md#binary-cache)).

## Secrets

`slop secret` lets agents change age secrets without the dev key. The broker's own age identity
(`palace/slop-broker-age.key`, public key `.keys/slop-broker.pub`) is in `defaultKeys` in
[`secrets.nix`](../secrets.nix), so every secret is encrypted to it; adding it took one full rekey.

- The agent sends the `.age` file from its checkout, and the broker returns new ciphertext, which
  the agent commits. Recipients come from the agent's `secrets.nix`.
- Before approval, the builder fetches `master`, looks the file's content up there and evaluates
  `master`'s `secrets.nix`. The approval says which file the content really is and whether the
  recipients match `master`'s rules for it (see the
  [design](https://git.nul.ie/dev/slop-broker/src/branch/main/docs/design.md#secrets)).
- `secrets.names` labels `dev` and `slop-broker` in approvals (`lib.my.c.ageKeyFiles`); host keys
  are shown abbreviated.

### `master` is protected

Deploy approvals ("on the branch", the diff since `master`) and secret approvals both trust
`master`, so only Dev may push to it or merge into it: branch protection on `dev/nixfiles` in Gitea
refuses everyone else, including the bot user that agents on `slop-cannon` push as.

## Approvals web app

`middleman` proxies `approve.slop.nul.ie` to port 8095 on `palace`. Approvers sign in through
Pocket ID at `id.nul.ie` (client `slop-approve`, restricted to the group `slop-approvers`; its
secret is `palace/slop-broker-oidc-secret`). Deploys to the routers (`river`, `stream` and
`estuary`) need a fresh passkey. See the
[design](https://git.nul.ie/dev/slop-broker/src/branch/main/docs/design.md#approvals-web-app).

## `slop.nul.ie`

`slop.nul.ie` replaces `paseo.nul.ie` for the Paseo web app on `middleman` (`paseoWebUi` in
`vhosts.nix`, `app.baseUrl` in `slop-cannon.nix`), and `*.slop.nul.ie` is reserved for previews.
The relay stays on `paseo-relay.nul.ie` for now, because existing pairings use that hostname.

Previews on `*.slop.nul.ie` will be same-site with every other `nul.ie` service, so a preview page
can set cookies on `.nul.ie` and browsers send `SameSite=Lax` cookies (including the SSO session)
with its requests to other `nul.ie` services. A separate domain would avoid this; `nul.ie` is kept
for simplicity.

## Rollout

Each step updates this page, the box pages and `AGENTS.md` as it lands.

1. **Done:** `slop.nul.ie`; the broker core, box queries, SSH transport, deploys and builds on
   `palace`; `castle` over SSH; Pocket ID at `id.nul.ie`; the approvals web app; secrets.
2. **DNS**, with a Cloudflare token of the broker's own for the public zones.
3. **Previews** on `*.slop.nul.ie`, through `middleman`.
4. **TCP forwards and a cache for VM builds**, if needed.
