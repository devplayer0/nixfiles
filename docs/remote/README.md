# Remote boxes

The "remote" group covers the boxes that live outside the `colony` and `home` sites: the two
edge VPSes (`britway` in London, `britnet` in Birmingham) and the `kelder` site — a secondary
server at a remote location, linked back to colony over WireGuard and acting as a NixOS
container host.

| Box | What it is | Docs |
| --- | --- | --- |
| `britway` | Vultr VPS (London, `lon1`): Headscale control plane, Tailscale exit node, BGP edge, nginx | [britway.md](britway.md) |
| `britnet` | VPS (Birmingham, `bhx1`): Tailscale exit node / WireGuard hub | [britnet.md](britnet.md) |
| `kelder` | Secondary home server (`hentai.engineer`): container host, Samba, DDNS | [kelder.md](kelder.md) |
| `kelder-acquisition` | Media stack container on `kelder` (Transmission over VPN, *arr, Jellyfin) | [kelder-acquisition.md](kelder-acquisition.md) |
| `kelder-spoder` | Web container on `kelder` (Nextcloud + nginx reverse proxy) | [kelder-spoder.md](kelder-spoder.md) |
