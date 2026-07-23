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
[river.md](river.md); the logical network map in [networking.md](../../networking.md).

## The switches

| | jim | dave | brian |
|---|---|---|---|
| Identity | `jim-sw` | `dave-sw` | (UniFi) |
| Model | CRS326-24G-2S+ | CRS504-4XQ | Ubiquiti 10GBASE-T |
| Switch chip | Marvell 98DX3236 | Marvell 98DX4310 (+ Atheros 8227 for the 1G mgmt port) | — |
| OS | RouterOS 7.18 | RouterOS 7.18 | UniFi |
| Ports | 24×1G + 2×SFP+ | 4×QSFP28 (100G, breakout-capable) + 1G mgmt | 10GBASE-T |
| Bridge | `main`, `vlan-filtering=yes` | `main`, `vlan-filtering=yes` | UniFi VLAN profiles |

jim and dave run a single hardware-offloaded bridge (`main`) with VLAN filtering. Access to the
MikroTiks is SSH as `admin` / `admin` by short hostname (see [Accessing the switches](#accessing-the-switches)).
Only jim and dave can do hardware VLAN translation (`/interface ethernet switch rule` on the Marvell
chips); brian cannot rewrite tags, only trunk/PVID them.

## Physical topology

The ONT terminates on brian; jim's `wan-pon-in` (`sfp-sfpplus2`) is a spare SFP+ port.

```
                                                  Virgin Media cable modem
                                                            │
                                                            │ (VLAN 130)
                                                            │ wan1/wan2/wan-in
       ┌──────────────────────────────────────────────────┴──┐
       │  jim   CRS326-24G-2S+  (Marvell 98DX3236)             │
       │  1G edge ports: castle, fort, pronter, laptop-dock,   │
       │  palace-kvm, ups, ether15-20, wan1/wan2/wan-in        │
       │  wan-pon-in (= sfp-sfpplus2)  ← spare SFP+            │
       └───────┬───────────────────────────────────┬─────────┘
   dave-uplink ┤ (= sfp-sfpplus1)                    │ stream, palace (1G secondaries)
       10G trunk│                                     └── stream (box, dual-homed)
       ┌─────────┴───────────────────────────────────────────────┐
       │  dave   CRS504-4XQ  (Marvell 98DX4310)                    │
       │  jim-downlink = qsfp28-3-1                                │
       └──┬───────────┬──────────┬───────────────────┬────────────┘
palace(100G)          │ castle   │ stream            │ brian-downlink
= qsfp28-1-1          │          │                   │ (802.3ad LAG: brian1+brian2)
     ┌────────────────┴─┐        …                   │
     │ palace host      │              Digiweb (PPPoE) via ONT
     │  └ river (VM)    │                       │
     └──────────────────┘                 ┌─────┴─────┐
   ↑ river's WAN + LAN ride the 100G link │    ONT    │ untagged mgmt 192.168.100.1
                                          └─────┬─────┘ + tagged VLAN 10 (ISP)
                                                │
                                       ┌────────┴────────┐
                                       │  brian (UniFi)  │  PVID 140 on the ONT port,
                                       │  10GBASE-T      │  tagged VLAN 10 allowed through
                                       └────────┬────────┘
                                                └── brian-downlink LAG up to dave
```

Notes:
- **river** runs as a VM on the **palace** host; its uplink is dave's 100G `palace` port. jim also
  has 1G `palace`/`stream` ports, but those are secondary links and do **not** carry the WAN.
- **stream** (the second router box) is dual-homed to both jim and dave (STP picks the active path).
- **brian** is a Ubiquiti 10GBASE-T switch, downlinked from dave over an **802.3ad LAG**
  (`brian-downlink` = `brian1` + `brian2`, layer-2 hash). It hosts the ONT.

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
L3 interface.

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
ONT ──(untagged + VLAN10)── brian ──(VLAN140 + VLAN10)── dave ──(VLAN140 + VLAN10)── river
        ONT port             │ PVID140 + tagged 10        │ plain bridging
                             └─ brian-downlink LAG ── dave ┘
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

## Accessing the switches

The switches resolve by **short hostname** on the home network — the home routers serve their
records in the home zone
([`nixos/boxes/home/routing-common/dns.nix`](../../../nixos/boxes/home/routing-common/dns.nix):
`jim` → hi `.10`, `dave` → hi `.11`, `brian` → core `.13`). From a box on the home network just
`ssh admin@jim` / `admin@dave`. Non-interactive pattern (password auth, avoids the ssh-agent hang):

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
