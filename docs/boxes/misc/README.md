# misc

Everything that isn't part of the `colony` or `home` sites: the edge VPSes, the
remote `kelder` site, a workstation, and the installer image.

| Machine | What it is | Docs |
| --- | --- | --- |
| `britway` | Vultr VPS (London, `lon1`): Headscale, Tailscale exit node, BGP edge, nginx | [britway.md](britway.md) |
| `britnet` | VPS (Birmingham, `bhx1`): Tailscale/WireGuard gateway | [britnet.md](britnet.md) |
| `kelder` | Remote site host (`hentai.engineer`): NixOS container host | [kelder.md](kelder.md) |
| `tower` | Framework Laptop 13 (12th-gen Intel) workstation | [tower.md](tower.md) |
| `installer` | Custom NixOS installer image | [installer.md](installer.md) |

## kelder containers

`kelder` is itself a container host (like `shill`/`sfh`):

| Container | Role | Docs |
| --- | --- | --- |
| `kelder-acquisition` | Media stack (Jellyfin + *arr + Transmission) | [kelder-acquisition.md](kelder-acquisition.md) |
| `kelder-spoder` | nginx web host | [kelder-spoder.md](kelder-spoder.md) |
