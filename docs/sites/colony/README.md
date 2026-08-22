# colony

The hosted dedicated server in Amsterdam (`ams1`) and the public-facing half of
the boxes: almost everything reachable from the internet lives here.

- **Internal domain:** `ams1.int.nul.ie` (`lib.my.c.colony.domain`)
- **Public domain:** `nul.ie` — public services are published as `*.nul.ie`
- **Source:** [`nixos/boxes/colony/`](../../../nixos/boxes/colony)

## Networking

`colony` separates the host, VMs, `shill` containers and `whale2` OCI workloads onto dedicated
networks behind [`estuary`](estuary.md), which terminates the public addressing. The canonical
prefixes and routing overview are in the [`colony` section of networking.md](../../networking.md#colony).

## Boxes

| Box | Role |
|---|---|
| [`colony`](colony.md) | Physical VM host (AMD, KVM, LVM-thin, `borgthin` backups → rsync.net) |
| [`estuary`](estuary.md) | Edge router: WAN, firewall/NAT, DNS, BGP (AS211024), WireGuard |
| [`shill`](shill/README.md) | NixOS container host (most applications; per-container pages under `shill/`) |
| [`whale2`](whale2.md) | podman/OCI game-server host |
| [`git`](git.md) | Gitea + Gitea Actions runner |
| [`mail`](mail.md) | Debian VM running mailcow (not NixOS) |
| [`darts`](darts.md) | Third-party/customer VM (not NixOS) |
| [`portcullis`](portcullis.md) | Bare-metal edge box for Nikhef; being staged, not yet in service |

The applications running on `shill` are listed on its own page — see
[shill/README.md](shill/README.md#containers).

`mail` and `darts` are host-defined VMs whose guest operating systems are managed out of band; their
pages document only what this repository controls.

`portcullis` is new hardware headed for Nikhef that will take over most of `estuary`'s edge routing.
It is not deployed yet and the resulting topology is still being worked out. It travels with
[`fergal`](fergal.md), an OpenWrt SFP+ switch whose firmware this flake builds; both are staged at
home for now, borrowing the home fabric through
[jim](../home/switches.md#fergal-portculliss-switch).
