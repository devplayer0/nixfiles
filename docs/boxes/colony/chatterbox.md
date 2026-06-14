# chatterbox

The Matrix homeserver (`nul.ie`) and its chat-network bridges.

- **Source:** [`shill/containers/chatterbox.nix`](../../../nixos/boxes/colony/vms/shill/containers/chatterbox.nix)
- **Host:** NixOS container on `shill`

## Role

- **Matrix homeserver** for `server_name = "nul.ie"`.
- **Bridges** to other chat networks:
  - `heisenbridge` (IRC),
  - `mautrix-whatsapp` (WhatsApp),
  - `mautrix-meta` / `mautrix-messenger` (Facebook Messenger / Instagram).
- Fronted by `middleman` (federation on `:8448`).

## Networking

- `internal` assignment on the `ctrs` network (alt name `chatterbox-ctr`).
