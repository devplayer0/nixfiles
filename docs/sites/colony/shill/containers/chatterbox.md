# chatterbox

The Matrix homeserver for `nul.ie` (Synapse) and its bridges to other chat networks.
[middleman](middleman.md) fronts it as `matrix.nul.ie` for clients and on `:8448` for
federation.

- **Source:** [`shill/containers/chatterbox.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/chatterbox.nix)
- **Host:** NixOS container on [`shill`](../../shill.md)

## Role

- **matrix-synapse** — `server_name = "nul.ie"`, `public_baseurl = https://matrix.nul.ie`,
  Element at `element.nul.ie` as the web client. Listens on `[::]:8008` (client + federation
  resources, `x_forwarded`) with a localhost manhole on `:9000`. Registration and guest access
  are disabled; uploads up to 1024M with dynamic thumbnails and URL previews enabled (previews
  are limited to [middleman](middleman.md)'s addresses as the fetch proxy).
- **heisenbridge** — IRC bridge, owner `@dev:nul.ie`, exclusive `@irc_*` user namespace.
- **mautrix-whatsapp** — WhatsApp bridge (appservice `whatsapp2`, `!wa` commands).
- **mautrix-meta** — two instances, `messenger` (`fbm2_*`, `!fbm`) and `instagram` (`ig_*`,
  `!ig`), both with backfill enabled.
- All three mautrix bridges use Postgres on [colony-psql](colony-psql.md) (URIs in their secret
  env files), require end-to-end encryption by default, and double-puppet onto `nul.ie` via the
  shared `doublepuppet.yaml` appservice registration (an age secret).
- The firewall allows `8008` (Synapse) and `8009` besides netdata.

## Network assignments

<!-- assignments: chatterbox -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| chatterbox-ctr | internal | `10.100.2.5/24 gw 10.100.2.1` | `2a0e:97c0:4d2:12::5/64` | ams1.int.nul.ie |  |
<!-- assignments-end -->

## Notes

- Synapse's real database config lives in the `chatterbox/synapse.yaml` age secret — options
  only merge at the top level, so the base config carries a dummy `sqlite3` block to satisfy
  the module defaults. The signing key is also an age secret.
- `olm-3.2.16` is allowed via `permittedInsecurePackages` (a nixpkgs E2EE library issue).
- The bridge services get `ffmpeg` on their `PATH` for GIF→video conversion.

## Notable config files

- [`nixos/boxes/colony/vms/shill/containers/chatterbox.nix`](../../../../../nixos/boxes/colony/vms/shill/containers/chatterbox.nix) — container definition, Synapse settings and all bridge configuration
