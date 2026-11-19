# slop-broker

[`slop-broker`](https://git.nul.ie/dev/slop-broker) carries out privileged operations (SSH
commands, deploys, builds, and later secrets, DNS and previews) for the coding agents on
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
| [`object`](sites/colony/shill/containers/object.md) | The binary cache that `slop build` pushes to |
| [`middleman`](sites/colony/shill/containers/middleman.md) | Publishes the approvals web app at `approve.slop.nul.ie`, Pocket ID at `id.nul.ie` and Paseo's web app at `slop.nul.ie` |

`palace`'s configuration is [`palace/slop-broker.nix`](../nixos/boxes/home/palace/slop-broker.nix):
the requesters, the `agent` policy they share, the secrets, and the web app settings. Its SSH
targets are the deploy-rs nodes on `master`, which the builder reads there, so a new box is a
target once it's merged.

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

## Binary cache

`slop build` pushes into Harmonia's store on `object` as `harmonia`, whose broker key is limited to
the store protocol and GC roots (`services.slop-broker-cache` in `object`'s configuration). CI
collects garbage in that store on every run, which the roots survive until they expire (see the
[design](https://git.nul.ie/dev/slop-broker/src/branch/main/docs/design.md#binary-cache)).

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
   `palace`; Pocket ID at `id.nul.ie`.
2. **Approvals web app:** remove the temporary `http://localhost:8095/auth/callback` from the
   `slop-approve` client, deploy `palace` and `middleman`.
3. **Secrets:** the broker's age identity joins `.keys/dev.pub` in the recipients that
   `secrets.nix` generates (one full rekey), so the dev key never goes to `palace`.
4. **DNS**, with a Cloudflare token of the broker's own for the public zones.
5. **Previews** on `*.slop.nul.ie`, through `middleman`.
6. **TCP forwards and a cache for VM builds**, if needed.
