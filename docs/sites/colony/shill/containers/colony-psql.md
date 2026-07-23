# colony-psql

The shared PostgreSQL instance for colony services. Rather than each service running its own
database, the containers (and the `git` VM) connect here over the `ctrs` network.

- **Source:** [`shill/containers/colony-psql.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/colony-psql.nix)
- **Host:** NixOS container on [`shill`](../../shill.md)

## Role

- **PostgreSQL 14** with TCP/IP enabled, reachable from the whole colony (`10.100.0.0/16` and
  `2a0e:97c0:4d2:10::/60`, `md5` auth). The firewall allows `5432`.
- Local `peer` auth maps `postgres`, `root`, `netdata` and `dev` to the `postgres` superuser via
  the ident map.
- **netdata** with the Python PostgreSQL collector.
- Consumers wait for the database to accept connections with the `lib.my.systemdAwaitPostgres`
  helper (e.g. `sharry`, `atticd`, `mastodon-init-db`, and `middleman`'s nginx as a DNS
  bootstrap hack).

## Network assignments

<!-- assignments: colony-psql -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| colony-psql-ctr (colony-psql) | internal | `10.100.2.4/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::4/64` | ams1.int.nul.ie |  |
<!-- assignments-end -->

The assignment also has the alt name `colony-psql` (no `-ctr` suffix), which is what consumers
use as the database hostname.

## Consumers

- [object](object.md) — `sharry` and `hedgedoc` (and `atticd` when enabled) over
  `colony-psql:5432`
- [toot](toot.md) — Mastodon's database (Mastodon currently disabled)
- [chatterbox](chatterbox.md) — the mautrix bridges (WhatsApp, Messenger, Instagram) via
  Postgres URIs in their secret env files
- `git` VM — Gitea

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/colony-psql.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/colony-psql.nix) — container definition and PostgreSQL configuration
