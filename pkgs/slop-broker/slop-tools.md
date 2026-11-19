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

| Command | What it does |
|---|---|
| `slop ssh <node> -- <command>…` | Run a command over SSH on a deploy node (as the deploy user, with `doas` for root). |
| `slop ssh --host <user>@<host> [-p <port>] -- <command>…` | The same for a host outside the deploy nodes. |
| `slop requests` | Your pending requests and active leases. |

- `--json` prints structured results (such as `slop requests`) as JSON.

- The remote command is joined with spaces and run by the remote login shell, as with `ssh`. Boxes
  usually use `fish`, so pipe multi-statement scripts through `bash`:
  `slop ssh <node> -- bash -s < script.sh`.
- There is no TTY. Interactive programs won't work; use non-interactive flags (`--no-pager`,
  `-y`).
- stdin is forwarded once the request is approved.

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
