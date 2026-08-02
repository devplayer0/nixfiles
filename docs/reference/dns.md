# DNS records

The tables on this page are generated from live authoritative zone transfers by
`nix run .#update-docs-dns -- <zones...>`; CI keeps them current. The Nix DNS configuration is
the source of truth. Edit the prose and headings here, but not content between the DNS markers.

DHCP-managed records are excluded. The generator identifies them by `DHCID` and removes the
corresponding forward and reverse records. SOA records and TTLs are also omitted because they are
operational metadata rather than useful inventory.

## Colony

These zones are served by [`estuary`](../sites/colony/estuary.md); their source configuration is
[`estuary/dns.nix`](../../nixos/boxes/colony/vms/estuary/dns.nix).

### Forward zone: `ams1.int.nul.ie`

<!-- dns: ams1.int.nul.ie -->
<!-- dns-start -->
| Name | Type | Value |
|---|---|---|
| `@` | `ALIAS` | `estuary-vm.ams1.int.nul.ie.` |
| `@` | `NS` | `ns.ams1.int.nul.ie.` |
| `_acme-challenge` | `TXT (LUA)` | `generated at query time` |
| `andrey-cust` | `A` | `94.142.242.254` |
| `chatterbox-ctr` | `A` | `10.100.2.5` |
| `chatterbox-ctr` | `AAAA` | `2a0e:97c0:4d2:12::5` |
| `colony` | `A` | `94.142.241.224` |
| `colony` | `AAAA` | `2a0e:97c0:4d2:10::2` |
| `colony-psql` | `CNAME` | `colony-psql-ctr.ams1.int.nul.ie.` |
| `colony-psql-ctr` | `A` | `10.100.2.4` |
| `colony-psql-ctr` | `AAAA` | `2a0e:97c0:4d2:12::4` |
| `colony-routing` | `A` | `10.100.0.2` |
| `colony-vms` | `A` | `10.100.1.1` |
| `colony-vms` | `AAAA` | `2a0e:97c0:4d2:11::1` |
| `ctr` | `CNAME` | `shill-vm.ams1.int.nul.ie.` |
| `darts-cust` | `A` | `94.142.242.255` |
| `darts-cust` | `AAAA` | `2a0e:97c0:4d2:2001::1` |
| `enshrouded` | `A` | `94.142.240.44` |
| `enshrouded-oci` | `A` | `10.100.3.5` |
| `enshrouded-oci` | `AAAA` | `2a0e:97c0:4d2:13::5` |
| `estuary-vm` | `A` | `94.142.240.44` |
| `estuary-vm` | `AAAA` | `2a02:898:0:20::329:1` |
| `estuary-vm-base` | `A` | `10.100.0.1` |
| `estuary-vm-base` | `AAAA` | `2a0e:97c0:4d2:10::1` |
| `fw` | `CNAME` | `estuary-vm.ams1.int.nul.ie.` |
| `gam-ctr` | `A` | `10.100.2.11` |
| `gam-ctr` | `AAAA` | `2a0e:97c0:4d2:12::b` |
| `git-vm` | `A` | `94.142.241.117` |
| `git-vm` | `AAAA` | `2a0e:97c0:4d2:11::4` |
| `git-vm-routing` | `A` | `10.100.1.4` |
| `graeme` | `A` | `94.142.240.44` |
| `graeme` | `AAAA` | `2a0e:97c0:4d2:13::8` |
| `graeme-oci` | `A` | `10.100.3.8` |
| `graeme-oci` | `AAAA` | `2a0e:97c0:4d2:13::8` |
| `hillcrest-tun` | `A` | `10.100.5.2` |
| `http` | `A` | `94.142.240.44` |
| `http` | `AAAA` | `2a0e:97c0:4d2:12::2` |
| `jackflix-ctr` | `A` | `10.100.2.6` |
| `jackflix-ctr` | `AAAA` | `2a0e:97c0:4d2:12::6` |
| `jam-cust` | `A` | `10.100.100.4` |
| `jam-cust` | `AAAA` | `2a0e:97c0:4d2:2002::1` |
| `jam-fwd` | `A` | `94.142.241.225` |
| `john-valorant-tun` | `A` | `10.100.5.6` |
| `kevcraft` | `A` | `94.142.240.44` |
| `kevcraft` | `AAAA` | `2a0e:97c0:4d2:13::6` |
| `kevcraft-oci` | `A` | `10.100.3.6` |
| `kevcraft-oci` | `AAAA` | `2a0e:97c0:4d2:13::6` |
| `kinkcraft` | `A` | `94.142.240.44` |
| `kinkcraft` | `AAAA` | `2a0e:97c0:4d2:13::7` |
| `kinkcraft-oci` | `A` | `10.100.3.7` |
| `kinkcraft-oci` | `AAAA` | `2a0e:97c0:4d2:13::7` |
| `librespeed` | `CNAME` | `http.ams1.int.nul.ie.` |
| `mail-vm` | `A` | `94.142.241.227` |
| `mail-vm` | `AAAA` | `2a0e:97c0:4d2:2000::1` |
| `middleman-ctr` | `A` | `10.100.2.2` |
| `middleman-ctr` | `AAAA` | `2a0e:97c0:4d2:12::2` |
| `ns` | `ALIAS` | `estuary-vm.ams1.int.nul.ie.` |
| `object-ctr` | `A` | `10.100.2.7` |
| `object-ctr` | `AAAA` | `2a0e:97c0:4d2:12::7` |
| `oci` | `CNAME` | `whale-vm.ams1.int.nul.ie.` |
| `qclk-ctr` | `A` | `10.100.2.10` |
| `qclk-ctr` | `AAAA` | `2a0e:97c0:4d2:12::a` |
| `shill-vm` | `A` | `94.142.241.225` |
| `shill-vm` | `AAAA` | `2a0e:97c0:4d2:11::2` |
| `shill-vm-ctrs` | `A` | `10.100.2.1` |
| `shill-vm-ctrs` | `AAAA` | `2a0e:97c0:4d2:12::1` |
| `shill-vm-routing` | `A` | `10.100.1.2` |
| `simpcraft` | `A` | `94.142.240.44` |
| `simpcraft` | `AAAA` | `2a0e:97c0:4d2:13::3` |
| `simpcraft-oci` | `A` | `10.100.3.3` |
| `simpcraft-oci` | `AAAA` | `2a0e:97c0:4d2:13::3` |
| `simpcraft-staging` | `A` | `94.142.240.44` |
| `simpcraft-staging` | `AAAA` | `2a0e:97c0:4d2:13::4` |
| `simpcraft-staging-oci` | `A` | `10.100.3.4` |
| `simpcraft-staging-oci` | `AAAA` | `2a0e:97c0:4d2:13::4` |
| `terraria` | `A` | `94.142.240.44` |
| `terraria` | `AAAA` | `2a0e:97c0:4d2:12::b` |
| `toot-ctr` | `A` | `10.100.2.8` |
| `toot-ctr` | `AAAA` | `2a0e:97c0:4d2:12::8` |
| `valheim` | `A` | `94.142.240.44` |
| `valheim` | `AAAA` | `2a0e:97c0:4d2:13::2` |
| `valheim-oci` | `A` | `10.100.3.2` |
| `valheim-oci` | `AAAA` | `2a0e:97c0:4d2:13::2` |
| `vaultwarden-ctr` | `A` | `10.100.2.3` |
| `vaultwarden-ctr` | `AAAA` | `2a0e:97c0:4d2:12::3` |
| `vm` | `CNAME` | `colony.ams1.int.nul.ie.` |
| `waffletail-ctr` | `A` | `10.100.2.9` |
| `waffletail-ctr` | `AAAA` | `2a0e:97c0:4d2:12::9` |
| `whale-vm` | `A` | `94.142.241.226` |
| `whale-vm` | `AAAA` | `2a0e:97c0:4d2:11::3` |
| `whale-vm-routing` | `A` | `10.100.1.3` |
<!-- dns-end -->

### IPv4 reverse zone: `100.10.in-addr.arpa`

<!-- dns: 100.10.in-addr.arpa -->
<!-- dns-start -->
| Address | Name |
|---|---|
| `10.100.0.1` | `estuary-vm-base.ams1.int.nul.ie.` |
| `10.100.0.2` | `colony-routing.ams1.int.nul.ie.` |
| `10.100.1.1` | `colony-vms.ams1.int.nul.ie.` |
| `10.100.1.2` | `shill-vm-routing.ams1.int.nul.ie.` |
| `10.100.1.3` | `whale-vm-routing.ams1.int.nul.ie.` |
| `10.100.1.4` | `git-vm-routing.ams1.int.nul.ie.` |
| `10.100.2.1` | `shill-vm-ctrs.ams1.int.nul.ie.` |
| `10.100.2.2` | `middleman-ctr.ams1.int.nul.ie.` |
| `10.100.2.3` | `vaultwarden-ctr.ams1.int.nul.ie.` |
| `10.100.2.4` | `colony-psql-ctr.ams1.int.nul.ie.` |
| `10.100.2.5` | `chatterbox-ctr.ams1.int.nul.ie.` |
| `10.100.2.6` | `jackflix-ctr.ams1.int.nul.ie.` |
| `10.100.2.7` | `object-ctr.ams1.int.nul.ie.` |
| `10.100.2.8` | `toot-ctr.ams1.int.nul.ie.` |
| `10.100.2.9` | `waffletail-ctr.ams1.int.nul.ie.` |
| `10.100.2.10` | `qclk-ctr.ams1.int.nul.ie.` |
| `10.100.2.11` | `gam-ctr.ams1.int.nul.ie.` |
| `10.100.3.2` | `valheim-oci.ams1.int.nul.ie.` |
| `10.100.3.3` | `simpcraft-oci.ams1.int.nul.ie.` |
| `10.100.3.4` | `simpcraft-staging-oci.ams1.int.nul.ie.` |
| `10.100.3.5` | `enshrouded-oci.ams1.int.nul.ie.` |
| `10.100.3.6` | `kevcraft-oci.ams1.int.nul.ie.` |
| `10.100.3.7` | `kinkcraft-oci.ams1.int.nul.ie.` |
| `10.100.3.8` | `graeme-oci.ams1.int.nul.ie.` |
<!-- dns-end -->

### IPv6 reverse zone: `2.d.4.0.0.c.7.9.e.0.a.2.ip6.arpa`

<!-- dns: 2.d.4.0.0.c.7.9.e.0.a.2.ip6.arpa -->
<!-- dns-start -->
| Address | Name |
|---|---|
| `2a0e:97c0:4d2:10::1` | `estuary-vm-base.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:10::2` | `colony.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:11::1` | `colony-vms.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:11::2` | `shill-vm.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:11::3` | `whale-vm.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:11::4` | `git-vm.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:12::1` | `shill-vm-ctrs.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:12::2` | `middleman-ctr.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:12::3` | `vaultwarden-ctr.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:12::4` | `colony-psql-ctr.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:12::5` | `chatterbox-ctr.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:12::6` | `jackflix-ctr.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:12::7` | `object-ctr.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:12::8` | `toot-ctr.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:12::9` | `waffletail-ctr.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:12::a` | `qclk-ctr.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:12::b` | `gam-ctr.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:13::2` | `valheim-oci.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:13::3` | `simpcraft-oci.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:13::4` | `simpcraft-staging-oci.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:13::5` | `enshrouded-oci.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:13::6` | `kevcraft-oci.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:13::7` | `kinkcraft-oci.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:13::8` | `graeme-oci.ams1.int.nul.ie.` |
| `2a0e:97c0:4d2:2000::1` | `mail.nul.ie.` |
| `2a0e:97c0:4d2:2001::1` | `darts-cust.ams1.int.nul.ie.` |
<!-- dns-end -->

## Home

These zones are served by [`river`](../sites/home/river.md) and
[`stream`](../sites/home/stream.md); their shared source configuration is
[`routing-common/dns.nix`](../../nixos/boxes/home/routing-common/dns.nix).

### Forward zone: `h.nul.ie`

<!-- dns: h.nul.ie -->
<!-- dns-start -->
| Name | Type | Value |
|---|---|---|
| `@` | `NS` | `ns1.h.nul.ie.` |
| `@` | `NS` | `ns2.h.nul.ie.` |
| `boot` | `CNAME` | `river-hi.h.nul.ie.` |
| `brian` | `A` | `192.168.64.13` |
| `castle` | `A` | `192.168.68.40` |
| `castle` | `AAAA` | `2a0e:97c0:4d0:1::3:1` |
| `cellar` | `A` | `192.168.68.80` |
| `cellar` | `AAAA` | `2a0e:97c0:4d0:1::4:1` |
| `dave` | `A` | `192.168.68.11` |
| `dave` | `AAAA` | `2a0e:97c0:4d0:1::1:2` |
| `dave-core` | `A` | `192.168.64.11` |
| `dave-lo` | `A` | `192.168.72.11` |
| `dave-lo` | `AAAA` | `2a0e:97c0:4d0:2::1:2` |
| `dyn` | `NS` | `ns1.dyn.h.nul.ie.` |
| `dyn` | `NS` | `ns2.dyn.h.nul.ie.` |
| `frigate` | `CNAME` | `hass-ctr.h.nul.ie.` |
| `hass-ctr` | `A` | `192.168.68.103` |
| `hass-ctr` | `AAAA` | `2a0e:97c0:4d0:1::5:3` |
| `hass-ctr-lo` | `A` | `192.168.72.103` |
| `hass-ctr-lo` | `AAAA` | `2a0e:97c0:4d0:2::5:3` |
| `jim` | `A` | `192.168.68.10` |
| `jim` | `AAAA` | `2a0e:97c0:4d0:1::1:1` |
| `jim-core` | `A` | `192.168.64.10` |
| `jim-lo` | `A` | `192.168.72.10` |
| `jim-lo` | `AAAA` | `2a0e:97c0:4d0:2::1:1` |
| `nixlight` | `A` | `192.168.72.46` |
| `ns1` | `ALIAS` | `river.h.nul.ie.` |
| `ns1.dyn` | `ALIAS` | `river.h.nul.ie.` |
| `ns2` | `ALIAS` | `stream.h.nul.ie.` |
| `ns2.dyn` | `ALIAS` | `stream.h.nul.ie.` |
| `palace` | `A` | `192.168.68.22` |
| `palace` | `AAAA` | `2a0e:97c0:4d0:1::2:1` |
| `palace-core` | `A` | `192.168.64.20` |
| `palace-kvm` | `A` | `192.168.72.21` |
| `reolink-living-room` | `A` | `192.168.72.45` |
| `river` | `A (LUA)` | `generated at query time` |
| `river` | `AAAA` | `2a0e:97c0:4df:0:1::1` |
| `river-core` | `A` | `192.168.64.1` |
| `river-hi` | `A` | `192.168.68.1` |
| `river-hi` | `AAAA` | `2a0e:97c0:4d0:1::1` |
| `river-lo` | `A` | `192.168.72.1` |
| `river-lo` | `AAAA` | `2a0e:97c0:4d0:2::1` |
| `river-ut` | `A` | `192.168.80.1` |
| `river-ut` | `AAAA` | `2a0e:97c0:4d0:3::1` |
| `router-hi` | `A` | `192.168.71.254` |
| `router-hi` | `AAAA` | `2a0e:97c0:4d0:1::ffff` |
| `router-lo` | `A` | `192.168.79.254` |
| `router-lo` | `AAAA` | `2a0e:97c0:4d0:2::ffff` |
| `router-ut` | `A` | `192.168.80.254` |
| `router-ut` | `AAAA` | `2a0e:97c0:4d0:3::ffff` |
| `sfh` | `A` | `192.168.68.81` |
| `sfh` | `AAAA` | `2a0e:97c0:4d0:1::4:2` |
| `shytzel` | `A` | `192.168.64.12` |
| `stream` | `A (LUA)` | `generated at query time` |
| `stream` | `AAAA` | `2a0e:97c0:4df:0:1::2` |
| `stream-core` | `A` | `192.168.64.2` |
| `stream-hi` | `A` | `192.168.68.2` |
| `stream-hi` | `AAAA` | `2a0e:97c0:4d0:1::2` |
| `stream-lo` | `A` | `192.168.72.2` |
| `stream-lo` | `AAAA` | `2a0e:97c0:4d0:2::2` |
| `stream-ut` | `A` | `192.168.80.2` |
| `stream-ut` | `AAAA` | `2a0e:97c0:4d0:3::2` |
| `unifi-ctr` | `A` | `192.168.68.100` |
| `unifi-ctr` | `AAAA` | `2a0e:97c0:4d0:1::5:1` |
| `unifi-ctr-core` | `A` | `192.168.64.21` |
| `ups` | `A` | `192.168.72.20` |
| `vibe` | `A` | `192.168.68.15` |
| `vibe` | `AAAA` | `2a0e:97c0:4d0:1::1:6` |
| `vibe-core` | `A` | `192.168.64.15` |
| `vibe-lo` | `A` | `192.168.72.15` |
| `vibe-lo` | `AAAA` | `2a0e:97c0:4d0:2::1:6` |
| `wave` | `A` | `192.168.72.14` |
| `wave` | `AAAA` | `2a0e:97c0:4d0:2::1:5` |
| `wave-core` | `A` | `192.168.64.14` |
<!-- dns-end -->

### IPv4 reverse zone: `168.192.in-addr.arpa`

<!-- dns: 168.192.in-addr.arpa -->
<!-- dns-start -->
| Address | Name |
|---|---|
| `192.168.64.1` | `river-core.h.nul.ie.` |
| `192.168.64.2` | `stream-core.h.nul.ie.` |
| `192.168.64.20` | `palace-core.h.nul.ie.` |
| `192.168.64.21` | `unifi-ctr-core.h.nul.ie.` |
| `192.168.68.1` | `river-hi.h.nul.ie.` |
| `192.168.68.2` | `stream-hi.h.nul.ie.` |
| `192.168.68.22` | `palace.h.nul.ie.` |
| `192.168.68.40` | `castle.h.nul.ie.` |
| `192.168.68.80` | `cellar.h.nul.ie.` |
| `192.168.68.81` | `sfh.h.nul.ie.` |
| `192.168.68.100` | `unifi-ctr.h.nul.ie.` |
| `192.168.68.103` | `hass-ctr.h.nul.ie.` |
| `192.168.71.254` | `router-hi.h.nul.ie.` |
| `192.168.72.1` | `river-lo.h.nul.ie.` |
| `192.168.72.2` | `stream-lo.h.nul.ie.` |
| `192.168.72.103` | `hass-ctr-lo.h.nul.ie.` |
| `192.168.79.254` | `router-lo.h.nul.ie.` |
| `192.168.80.1` | `river-ut.h.nul.ie.` |
| `192.168.80.2` | `stream-ut.h.nul.ie.` |
| `192.168.80.254` | `router-ut.h.nul.ie.` |
<!-- dns-end -->

### IPv6 reverse zone: `0.d.4.0.0.c.7.9.e.0.a.2.ip6.arpa`

<!-- dns: 0.d.4.0.0.c.7.9.e.0.a.2.ip6.arpa -->
<!-- dns-start -->
| Address | Name |
|---|---|
| `2a0e:97c0:4d0:1::1` | `river-hi.h.nul.ie.` |
| `2a0e:97c0:4d0:1::2` | `stream-hi.h.nul.ie.` |
| `2a0e:97c0:4d0:1::ffff` | `router-hi.h.nul.ie.` |
| `2a0e:97c0:4d0:1::2:1` | `palace.h.nul.ie.` |
| `2a0e:97c0:4d0:1::3:1` | `castle.h.nul.ie.` |
| `2a0e:97c0:4d0:1::4:1` | `cellar.h.nul.ie.` |
| `2a0e:97c0:4d0:1::4:2` | `sfh.h.nul.ie.` |
| `2a0e:97c0:4d0:1::5:1` | `unifi-ctr.h.nul.ie.` |
| `2a0e:97c0:4d0:1::5:3` | `hass-ctr.h.nul.ie.` |
| `2a0e:97c0:4d0:2::1` | `river-lo.h.nul.ie.` |
| `2a0e:97c0:4d0:2::2` | `stream-lo.h.nul.ie.` |
| `2a0e:97c0:4d0:2::ffff` | `router-lo.h.nul.ie.` |
| `2a0e:97c0:4d0:2::5:3` | `hass-ctr-lo.h.nul.ie.` |
| `2a0e:97c0:4d0:3::1` | `river-ut.h.nul.ie.` |
| `2a0e:97c0:4d0:3::2` | `stream-ut.h.nul.ie.` |
| `2a0e:97c0:4d0:3::ffff` | `router-ut.h.nul.ie.` |
<!-- dns-end -->
