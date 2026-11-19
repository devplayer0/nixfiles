# Privileged operations through `slop`

You don't have credentials for other boxes or services. Instead, the `slop` command asks a broker
outside this environment to carry out privileged operations for you. The broker holds the keys,
applies a policy, and asks a human to approve most requests.

## How requests behave

- A request that needs approval blocks for up to **five minutes** while a human answers. Run
  `slop` with a tool timeout of at least six minutes, or in the background. Don't retry a request
  that is waiting, denied or expired in a loop; tell the user instead.
- Exit status **125** means the broker did not run the operation: it was denied, expired, invalid
  or failed. Any other status is the operation's own.
- Approvers see who sent a request and can see `--label` (or `SLOP_LABEL`). Use it to say briefly
  why you need it, e.g. `--label "checking nginx after config change"`.
- Approvers may grant a lease, so repeats of the same request (same target) may run without
  waiting. `slop requests` shows your pending requests and leases.
- Anything a command prints ends up in your context and transcript. Avoid printing secrets.

## Commands

| Command | What it does | Approval |
|---|---|---|
| `slop status <node> [unit]` | `systemctl status`, of one unit or the whole box | usually none |
| `slop logs <node> <unit> [-n 200] [--since 2h]` | A unit's journal; `--since` takes a duration or a date (`2026-01-31 12:00`) | usually none |
| `slop failed <node>` | Failed units | usually none |
| `slop ssh <node> -- <command>…` | Any command over SSH, as the deploy user (with `doas` for root) | asks |
| `slop deploy <node>… [--commit <rev>] [--boot]` | Build a pushed commit and deploy it to all the nodes at once | asks |
| `slop requests` | Your pending requests and active leases | none |

- Prefer `status`, `logs` and `failed` to `slop ssh` for looking at a box: they don't wait for a
  human.
- Every box command also takes `--host <user>@<host> [-p <port>]` instead of a node, for hosts
  outside the deploy nodes.
- `--json` prints structured results (such as `slop requests`) as JSON.
- For `slop ssh`, the remote command is joined with spaces and run by the remote login shell, as
  with `ssh`. Boxes usually use `fish`, so pipe multi-statement scripts through `bash`:
  `slop ssh <node> -- bash -s < script.sh`.
- There is no TTY. Interactive programs won't work; use non-interactive flags (`--no-pager`,
  `-y`).
- `slop ssh` forwards stdin once the request is approved.

### Deploying

- Push the commit first: the broker fetches it from Gitea, not from you, and only finds commits
  on a branch. `--commit` defaults to `HEAD` of your checkout (with `jj`, pass the commit).
- A target is a node (all its profiles, like `deploy .#node`) or `node.profile`, such as
  `shill.container-middleman`. Several targets deploy in parallel; for an order, deploy them one
  at a time.
- The build and the copy to the nodes happen before approval, and their output streams to you,
  so build errors show up without waiting for a human. Approval waits start after that.
- `--boot` makes it the boot default without switching; the box uses it after its next reboot.
- Check the result afterwards with `slop failed` and `slop status`.

## Don't

- Don't try to find, read or copy the broker's credentials, or use `deploy`, `ssh-machine` or
  `.keys/` directly. They won't work from here, and trying is a policy violation.
- Don't ask for broader access than the task needs.

## Suggest new operations

`slop` grows one operation at a time. If you find yourself working around a missing operation, or
making the same `slop ssh` request (and waiting for approval) again and again for something that
could be a fixed, checkable operation, tell the user. Say what the operation would do, which
arguments it would take, and whether it could run without approval. Don't build the workaround
into a habit instead.
