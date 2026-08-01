# Remote boxes

The "remote" group covers the boxes that live outside the `colony` and `home` sites: the two
edge VPSes (`britway` in London, `britnet` in Birmingham) and the `kelder` site — a secondary
server at a remote location, linked back to colony over WireGuard and acting as a NixOS
container host.

| Box | What it is |
| --- | --- |
| [`britway`](britway.md) | Vultr VPS (London, `lon1`): Headscale control plane, Tailscale exit node, BGP edge, nginx |
| [`britnet`](britnet.md) | VPS (Birmingham, `bhx1`): Tailscale exit node / WireGuard hub |
| [`kelder`](kelder/README.md) | Secondary home server (`hentai.engineer`): container host, Samba, DDNS (containers on its page) |
