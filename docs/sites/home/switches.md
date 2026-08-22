# Home switches

Reference for the two MikroTik switches on the home network — **jim** and **dave** — plus the
Ubiquiti switch **brian**, and how the home boxes and the Digiweb WAN hang off them. These switches
are **not** managed by this flake; they are configured by hand (RouterOS on jim/dave, UniFi on
brian). It covers the physical topology, the VLAN map, and how the Digiweb WAN reaches river.

In short: the Digiweb ISP VLAN (10) is trunked straight through to river (which runs PPPoE on it),
and the ONT's untagged management is PVID'd onto VLAN 140 at brian, its edge switch. VLAN 10 is
carried untranslated because a single ONT makes it unique on the fabric — see
[the WAN path](#the-digiweb-wan-path-trunked-vlan-10--pvid-140) and
[why not translation](#why-not-translation-for-one-ont). The router side lives in
[river.md](river.md); the logical network map in [networking.md](../../networking.md). The Wi-Fi
APs that hang off these switches are in [aps.md](aps.md). A fourth switch, **fergal**, runs OpenWrt
and is on the bench rather than in the production path — see
[fergal](#fergal-the-openwrt-switch).

## The switches

| | jim | dave | brian |
|---|---|---|---|
| Identity | `jim-sw` | `dave-sw` | (UniFi) |
| Model | CRS326-24G-2S+ | CRS504-4XQ | Ubiquiti Switch Pro XG 8 PoE |
| Switch chip | Marvell 98DX3236 | Marvell 98DX4310 (+ Atheros 8227 for the 1G mgmt port) | — |
| OS | RouterOS | RouterOS | UniFi |
| Ports | 24×1G + 2×SFP+ | 4×QSFP28 (100G, breakout-capable) + 1G mgmt | 8×10GBASE-T PoE + 2×10G SFP+ |
| Bridge | `main`, `vlan-filtering=yes` | `main`, `vlan-filtering=yes` | UniFi VLAN profiles |

jim and dave run a single hardware-offloaded bridge (`main`) with VLAN filtering. Access to the
MikroTiks is SSH as `admin` / `admin` by short hostname (see [Accessing the switches](#accessing-the-switches)).
Only jim and dave can do hardware VLAN translation (`/interface ethernet switch rule` on the Marvell
chips); brian cannot rewrite tags, only trunk/PVID them.

## Physical topology

The two WAN sources enter at the top: the Virgin Media modem lands on **jim** (VLAN 130), and the
Digiweb **ONT** lands on **brian**. Both `jim` and `brian` are edge switches that uplink down into
the **dave** core; the home boxes hang off dave's 100G ports, with backup links up to jim. jim's
`wan-pon-in` (`sfp-sfpplus2`) is a spare SFP+ port, unused today.

```
  Virgin Media cable modem                         Digiweb ONT
  stream WAN, VLAN 130                             river WAN, management + VLAN 10
             |                                               |
            jim                                            brian
             | 10G trunk                         802.3ad LAG |
             +--------------------+          +---------------+
                                  |          |
                              +---+----------+---+
                              |      dave        |
                              +--------+---------+
                                       |
                 +---------------------+---------------------+
                 |                     |                     |
             palace (100G)         castle (100G)          stream
             river VM              NVMe-oF root           second router

  Backup links to jim (normally idle):
    * palace: 1G
    * stream: 1G; STP selects the active link
    * castle: 2.5G, normally down; no live failover
```

Notes:
- **river** runs as a VM on the **palace** host; its uplink is dave's 100G `palace` port. jim also
  has 1G `palace`/`stream` ports, but those are secondary links and do **not** carry the WAN.
- **stream** (the second router box) is dual-homed to both jim and dave (STP picks the active path).

### Castle storage dependency

`castle` is dual-homed without STP: its primary link is dave's 100G `castle` port (`et100g`), while
the 2.5G link to jim (`et2.5g`) is normally down and provides no live failover. Its root disk is
NVMe-oF over `et100g` and dave, so interrupting either freezes `castle` mid-I/O. Do dave maintenance
from a box that does not depend on it, or power `castle` off cleanly first.

## VLANs

| VLAN | Name | Purpose |
|---|---|---|
| — (native) | core | Switch management, `192.168.64.0/24` (jim `.10`, dave `.11`, brian `.13`) |
| 100 | hi | High-performance / jumbo network (MTU 9000) |
| 110 | lo | Standard LAN |
| 120 | untrusted | Guest / untrusted network |
| 130 | wan | **stream's WAN** — Virgin Media cable modem (untagged on jim's `wan1`/`wan2`/`wan-in`) |
| 140 | wan-pon-ont | ONT management, `192.168.100.0/24` (PVID'd at the ONT edge) |
| 10 | pon-isp | Digiweb ISP transport — **trunked straight through** to river, PPPoE runs on it |
| 141 | wan-pon-isp | **Reserved** — the translated ISP VLAN for the future multi-ONT design |

Switch L3 presence (`/interface vlan` on `main`) exists **only** for VLANs the switch is managed
from — `hi` (100) and `lo` (110), plus native core. WAN and guest VLANs deliberately have no switch
L3 interface. jim and dave carry a static IPv4 and **global IPv6** address on `hi`/`lo` (plus a
static default route on each stack) purely for management — they are **pure L2, never routers**. See
[Switches must not route](#switches-must-not-route).

## The Digiweb WAN path (trunked VLAN 10 + PVID 140)

The ONT presents two things on one wire:
- **untagged** management traffic (`192.168.100.x`), and
- **tagged VLAN 10** carrying the Digiweb ISP session (the BRAS requires VLAN 10).

With a **single ONT** there's no reason to translate anything — VLAN 10 is unique on the fabric, so
we just carry it end to end and let river run PPPoE directly on it:

1. **Untagged mgmt → VLAN 140, at the ONT's edge switch (brian).** brian sets the ONT port's PVID to
   140 so the untagged management traffic becomes VLAN 140, and allows tagged VLAN 10 through the
   same port. river takes `192.168.100.100/24` on VLAN 140 (matching stream's modem-mgmt `.100`) to
   reach the ONT web UI at `192.168.100.1`. Doing the PVID at the ONT-facing edge keeps it clean —
   the untagged frames never share a domain with anything else.

2. **VLAN 10 (ISP) trunked straight through, untranslated.** brian → dave → palace carry tagged
   VLAN 10 by ordinary bridge-VLAN membership. No `/interface ethernet switch rule`, no pinning, no
   asymmetric-learning issues — it's just a normal tagged VLAN. river attaches PPPoE to VLAN 10
   directly (`wan-pon-isp` netdev = VLAN `pon-isp` = 10; baby-jumbo MTU 1508 so PPP nets a clean
   1500).

Net result: **river runs PPPoE single-tagged on VLAN 10 and holds a VLAN 140 address to reach the
ONT.** See [`nixos/boxes/home/palace/vms/river.nix`](../../../nixos/boxes/home/palace/vms/river.nix)
for the river side.

```
ONT -- untagged + VLAN 10 -- brian -- VLAN 140 + VLAN 10 -- dave -- palace -- river
                              |
                              +-- ONT port PVID 140; VLAN 10 remains tagged
```

### Why not translation (for one ONT)?

Translation would swap VLAN 10 → 141 with two pinned hardware ACL rules to keep VLAN 10 off the rest
of the fabric. That buys nothing with a single ONT — VLAN 10 is already unique, so trunking it is
simpler and rule-free. Translation only earns its keep when **two** ONTs both deliver VLAN 10 and
would collide (below).

## Switch configuration

How each switch is set up for the Digiweb WAN path. **Confirm any change on the box before applying**
(see [Accessing the switches](#accessing-the-switches)).

**brian (UniFi)** — hosts the ONT:
- The ONT port has **native/untagged network = VLAN 140** (PVID) and is a **tagged member of VLAN 10**,
  so the ONT's untagged management lands on 140 and its tagged ISP frames pass through.
- The `brian-downlink` LAG up to dave trunks **tagged 140 + tagged 10** (alongside the LAN VLANs).

**dave (RouterOS)** — trunks both WAN-pon VLANs to `brian-downlink` and `palace`. The ISP VLAN 10 row:
```
/interface bridge vlan add bridge=main vlan-ids=10 tagged=brian-downlink,palace
```
VLAN 140 also spans `brian-downlink,palace` (it carries a few other members too). No switch rules —
this is plain tagged bridging.

**jim (RouterOS)** — carries **none** of the Digiweb WAN path: no translation rules, and no VLAN
10/140/141 rows. `wan-pon-in` (`sfp-sfpplus2`) sits at `pvid=1` as a spare port. jim only handles
stream's VLAN-130 WAN and the LAN VLANs.

## Switches must not route

jim and dave (and the `vibe` AP) are **pure L2** — river/stream do all routing. Their per-stack
management addresses and static default routes exist only so the boxes themselves can be reached and
reach out; they must **never** forward traffic or advertise themselves as routers. RouterOS defaults
work against this: `ip-forward` and IPv6 `forward` ship **on**, and with IPv6 forwarding on RouterOS
also emits Router Advertisements (`ra-lifetime=30m`) on every L3 interface — so a switch silently
becomes a competing IPv6 default router. This surfaced after the 7.18 → 7.23 upgrade, when clients
picked up dave/jim as default routers alongside river.

The required config on each RouterOS box:
```
/ip settings set ip-forward=no
/ipv6 settings set forward=no accept-router-advertisements=no
/ipv6 nd set [find] ra-lifetime=0
```
- `ip-forward=no` / `forward=no` — no L3 forwarding on either stack; IPv6 `forward=no` also stops RA
  emission at the source.
- `accept-router-advertisements=no` — with forwarding off RouterOS would otherwise start *accepting*
  RAs; this keeps the box on its deterministic **static** default route.
- `ra-lifetime=0` — belt-and-suspenders: even if forwarding is ever re-enabled the box advertises
  router-lifetime 0 (i.e. "not a default router"). Setting it also emits a withdrawal RA that
  actively clears the rogue default from clients (they otherwise cache it for up to ~30 min).

**After any RouterOS upgrade, re-check `/ip settings` and `/ipv6 settings`** — an upgrade can reset
these to the forwarding-on defaults. brian (UniFi) is not a RouterOS box and was not affected.

## Future: multiple ONTs (per-port VLAN translation)

If a second ONT arrives (e.g. a Digiweb line for stream, or a second river), trunking breaks: both
ONTs deliver **tagged VLAN 10**, and plain bridge-VLAN filtering can't tell them apart. That's when
translation earns its place — a switch rule matches on the **ingress port**, so each ONT's VLAN 10
becomes a *distinct* fabric VLAN:

- ONT-A port: VLAN 10 → **141** (→ river)
- ONT-B port: VLAN 10 → **142** (→ stream / second river)
- mgmt: PVID each ONT port onto its own VLAN (140, 143, …) so both ONTs' `192.168.100.1` stay in
  separate L2/L3 domains.

The forward direction isolates naturally (each ONT maps to a different fabric VLAN). The **return**
direction is where port targeting is mandatory: both translate *back* to VLAN 10, so bridge VLAN 10
now has two members and a plain FDB-miss flood would leak one ONT's upstream to the other. Each
return must be pinned to its port with `new-dst-ports`:
```
# ONT-A: 141 in on palace → 10, forced out ONT-A's port
# ONT-B: 142 in on stream → 10, forced out ONT-B's port
```
Each ONT port must also be a tagged member of bridge VLAN 10 for correct egress tagging (the missing
piece that otherwise shows up as pppd "Timeout waiting for PADO"). The pins bypass the FDB, so the
two ISP sessions never mix.

**Why a new switch:** jim (the only box with spare SFP+ *and* the translation feature) has just
**one** free SFP+ port, so it can't host two ONTs. The plan is a dedicated
**CRS305-1G-4S+** (4×SFP+, same Marvell rule support) to land multiple ONTs and do the per-port
translation there, feeding distinct fabric VLANs up to dave.

## fergal, the OpenWrt switch

An 8-port SFP+ switch — **XikeStor SKS8300-8X**, the board itself branded **ONTi ONT-S508CL-8S** —
on a Realtek RTL9303 (MIPS 34Kc, 512 MB RAM, 32 MiB SPI NOR). Unlike jim, dave and brian it runs
**OpenWrt**, so it is configured through UCI rather than RouterOS or a UniFi controller.

fergal is **not yet part of the fabric**: it sits at `192.168.64.30` on core (no DNS record yet),
still has the stock single-VLAN bridge with all eight ports untagged, and only one SFP+ cage is
populated. Treat it as bench equipment until that changes.

Its firmware *is* built by this flake — see
[OpenWrt images](../../deployment.md#openwrt-images) for the outputs and the feed pin. Packages are
baked into the image, so adding tooling means editing
[`openwrt/default.nix`](../../../openwrt/default.nix) and reflashing rather than installing on the
box.

### Flash layout

A single 32 MiB SPI NOR chip (`spi0.0`, 64 KiB erase blocks). `kernel` and `rootfs` are
sub-partitions of `firmware`, and OpenWrt adds `rootfs_data` as the JFFS2 overlay after a real
flash.

| Partition | Device | Offset | Size |
|---|---|---|---|
| `u-boot` | `mtd0` | `0x000000` | 1 MiB |
| `board-info` | `mtd1` | `0x100000` | 192 KiB |
| `syslog` | `mtd2` | `0x130000` | 832 KiB |
| `firmware` | `mtd3` | `0x200000` | 30 MiB |

**`board-info` is irreplaceable.** It holds the unit's MAC addresses (`[vlanmac]` / `[cpumac]`), its
`[license]` hash, the stock boot pointers and an SSH host key — only about 1.3 KiB of it is
non-blank, and none of it can be regenerated. A full dump of all four partitions, taken before
OpenWrt was flashed, is kept outside this repo — 33 MB of images, with per-partition checksums and
restore notes. Never write `u-boot` or `board-info` without a confirmed serial/TFTP recovery path.

### Flashing notes

The procedure itself is in [`openwrt-flash.md`](../../openwrt-flash.md); what follows is specific to
this board.

Stock u-boot boots `flash:/nos.img` from a JFFS2 filesystem, so OpenWrt's sysupgrade image is
itself a JFFS2 image containing `nos.img` rather than a raw kernel + squashfs. Two things bite when
flashing from an initramfs, as during the initial install:

- **`sysupgrade -c` does not work.** It needs `/overlay/upper/etc`, which doesn't exist when running
  from RAM, and it aborts *after* `mtd erase firmware` has already run — leaving the box with no
  bootable firmware until the job is finished. Pass the config as an explicit tarball instead
  (`tar czf`, then `sysupgrade -f <tarball> …`).
- **The working management address may not be in UCI.** If it was set by hand with `ip` while UCI
  still held the stock address, the box comes back unreachable. Write it into `network.lan` and
  commit before flashing.

Neither applies to an ordinary flash-to-flash upgrade, where `sysupgrade` keeps `/etc/config` and
the files listed in `/lib/upgrade/keep.d/` by default. Dropbear host keys are regenerated by a flash
that doesn't preserve them, so clear the old `known_hosts` entry afterwards.

## Accessing the switches

The switches resolve by **short hostname** on the home network — the home routers serve their
records in the home zone
([`nixos/boxes/home/routing-common/dns.nix`](../../../nixos/boxes/home/routing-common/dns.nix):
`jim` → hi `.10`, `dave` → hi `.11`, `brian` → core `.13`). From a box on the home network just
`ssh admin@jim` / `admin@dave`.

**Key auth** for `admin` is installed on jim/dave (and the `vibe` AP) — `ssh -i ~/.ssh/id_rsa
admin@jim` works keyless (imported via `/user ssh-keys import`). Password `admin`/`admin` remains as
a fallback. Non-interactive password pattern (avoids the ssh-agent hang) if the key isn't available:

```
sshpass -p admin ssh -o IdentityAgent=none -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=/tmp/sw_known_hosts admin@jim
```

**Always confirm config changes on the switch** (print the affected menu, apply, re-verify). brian
is UniFi — configured through its controller, not RouterOS CLI.

## Management IPs

| | core (`192.168.64.0/24`) | hi (`192.168.68.0/22`) | lo (`192.168.72.0/21`) |
|---|---|---|---|
| jim | `.10` (on `main`) | `.10` | `.10` |
| dave | `.11` (on `management`, the 1G Atheros port) | `.11` | `.11` |
| brian | `.13` (core) | — | — |
