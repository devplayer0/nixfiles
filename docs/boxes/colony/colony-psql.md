# colony-psql

The shared PostgreSQL instance for colony. Several other containers
(`middleman`, `chatterbox`, `toot`, `git`, …) connect here rather than each
running their own database.

- **Source:** [`shill/containers/colony-psql.nix`](../../../nixos/boxes/colony/vms/shill/containers/colony-psql.nix)
- **Host:** NixOS container on `shill`

## Role

- **PostgreSQL 14** serving the other colony services over the `ctrs` network.
  Consumers wait for it to be ready via the `systemdAwaitPostgres` helper.
- netdata for monitoring.

## Networking

- `internal` assignment on the `ctrs` network (alt name `colony-psql-ctr`).
