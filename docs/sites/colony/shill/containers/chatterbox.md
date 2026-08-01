# chatterbox

The Matrix homeserver for `nul.ie` (Synapse) and its bridges to other chat networks.
[middleman](middleman.md) fronts it as `matrix.nul.ie` for clients and on `:8448` for
federation.

- **Source:** [`shill/containers/chatterbox.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/chatterbox.nix)
- **Host:** NixOS container on [`shill`](../README.md)
- **nixpkgs:** `mine`

## Role

### Synapse

`matrix-synapse` serves `nul.ie` at `https://matrix.nul.ie`, with Element at `element.nul.ie`.
Port 8008 carries client and federation traffic with forwarded headers, while a localhost manhole
uses port 9000. Registration and guest access are disabled; uploads, dynamic thumbnails and URL
previews are enabled, with preview fetching restricted to [middleman](middleman.md).

### Bridges

The box runs heisenbridge for IRC, `mautrix-whatsapp`, and two `mautrix-meta` instances for
Messenger and Instagram. The mautrix bridges use [colony-psql](colony-psql.md), default to
end-to-end encryption, and share the secret `doublepuppet.yaml` registration for double puppeting
onto `nul.ie`. The firewall admits ports 8008 and 8009 in addition to netdata.

## Network assignments

See the consolidated [network assignments](../../../../networking.md#box-assignments) table (this box: `chatterbox`).

## Notes

- Synapse's real database config lives in the `chatterbox/synapse.yaml` age secret — options
  only merge at the top level, so the base config carries a dummy `sqlite3` block to satisfy
  the module defaults. The signing key is also an age secret.
- `olm-3.2.16` is allowed via `permittedInsecurePackages` (a nixpkgs E2EE library issue).
- The bridge services get `ffmpeg` on their `PATH` for GIF→video conversion.

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/chatterbox.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/chatterbox.nix) — container definition, Synapse settings and all bridge configuration
