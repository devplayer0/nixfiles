# kelder-spoder

An nginx web host on the `kelder` site.

- **Source:** [`kelder/containers/spoder/`](../../../nixos/boxes/kelder/containers/spoder)
  (`default.nix`, `nginx.nix`)
- **Host:** NixOS container on `kelder`

## Role

- Serves web content via **nginx** ([`nginx.nix`](../../../nixos/boxes/kelder/containers/spoder/nginx.nix)),
  with ACME-managed certificates (nginx in the `acme` group, reloads on renewal).
- Runs under the site's shared `kontent` user.

## Networking

- `internal` assignment (alt name `spoder-ctr`) on the kelder container network.
