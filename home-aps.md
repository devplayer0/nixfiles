# Home wireless APs

Reference for the home Wi-Fi access points. Like the switches (`home-switches.md`), these are **not**
managed by this flake — they are configured on-device (RouterOS on the MikroTik, OpenWrt/UCI on the
Cudy). This file documents the shared VLAN/trunk design and each AP.

Only the DNS records live in the flake (`nixos/boxes/home/routing-common/dns.nix`, `h.nul.ie` zone).
Everything else here is applied by hand on the device.

## The APs

| | vibe | wave |
|---|---|---|
| Model | MikroTik **cAP ax** (`cAPGi-5HaxD2HaxD`) | Cudy **AX3000** (OpenWrt id `cudy,ap3000-v1`) |
| OS | RouterOS 7.x | OpenWrt 25.12.x (MT7981B / Filogic 820) |
| Radio | 2×2 both bands | 2×2 both bands (2 spatial streams) |
| Uplink | trunk (multi-port; `ether2` is a wired LAN port) | single **2.5 GbE** trunk |
| Management | core/hi/lo `.15` | core/lo `.14` (**not** `hi`; see below) |

Both mirror the same two SSIDs. `wave` replaced an older AP of the same name; the new one is the
Cudy running OpenWrt.

> **Note on "AX3000":** MT7981B is 2×2 (2 spatial streams). The "3000" is *aggregate* Mbps —
> 574 (2.4 GHz 2ss) + 2402 (5 GHz 2ss @ **160 MHz**) — not three streams. `iw` confirms 2×2
> (`Available Antennas TX/RX 0x3`; "3 streams: not supported"). 160 MHz is what earns the "3000".

## Shared design (dumb AP)

Every AP is a **dumb AP**: it bridges wireless clients onto the right VLAN and does **no** routing,
DHCP, RA or firewalling. The home routers (`river`/`stream`) own DHCP/RA/gateway (per-VLAN VRRP VIPs)
and firewalling. The uplink is a **tagged trunk**:

| VLAN | `lib.my.c.home.vlans` | Role | AP use |
|---|---|---|---|
| — (native) | `core` | switch/fabric management (1500) | backup management (untagged) |
| 100 | `hi` | trusted LAN, **high-MTU** (jumbo 9000) | `vibe` management (it's jumbo-capable) |
| 110 | `lo` | trusted LAN (1500) | main SSID `wlan0`; `wave` management |
| 120 | `untrusted` | guest network | guest SSID `wlan1` |

`hi` and `lo` are both **trusted** client VLANs — the only difference is MTU (`hi` carries jumbo
9000, `lo` is standard 1500). An AP puts its own management on whichever it can do: `vibe` (jumbo)
sits on `hi`, `wave` (eth0 capped at 2026) sits on `lo`. The main SSID lands on `lo` because Wi-Fi
clients are 1500 regardless.

### SSIDs

| SSID | Bands | Security | VLAN |
|---|---|---|---|
| `wlan0` (main) | 5 GHz + 2.4 GHz | WPA2/WPA3-PSK (`sae-mixed`) | 110 (`lo`) |
| `wlan1` (guest) | 2.4 GHz | WPA2-PSK (`psk2`) | 120 (`untrusted`) |

**Passphrases are never stored in this repo.** `vibe` is the source of truth; read them out-of-band
with `ssh admin@vibe '/interface wifi export show-sensitive'` (`.passphrase=` prints **unquoted**).

## vibe (MikroTik cAP ax)

RouterOS, one hardware-offloaded bridge `main` with `vlan-filtering=yes`. Access: `ssh admin@vibe`
— key auth for `admin` is installed (`~/.ssh/id_rsa`), with `admin`/`admin` as a fallback.

- **Uplink `ether1`** — trunk, tagged VLANs 100/110/120; native/untagged is the default VLAN 1
  (PVID, no IP). `ether2` is a wired **access port** on VLAN 110 (`lo`). `l2mtu 9214`.
- **Radios** — `wifi1` (5 GHz, 20/40/80) + `wifi2` (2.4 GHz, 20/40) both broadcast `wlan0`
  (WPA2/WPA3-PSK), untagged onto VLAN 110. `wifi3` is a virtual AP on `wifi2` broadcasting `wlan1`
  (WPA2-PSK), untagged onto VLAN 120. `country=Ireland`.
- **Bridge VLANs** — 100 tagged `main,ether1`; 110 tagged `main,ether1` + untagged
  `ether2,wifi1,wifi2`; 120 tagged `main,ether1` + untagged `wifi3`.
- **Management** — `jim`/`dave`-style (core/hi/lo), on host `.15`: `192.168.64.15` on core
  (native/untagged, backup), `192.168.68.15/22` + `2a0e:97c0:4d0:1::1:6` on the `hi` VLAN-100
  interface (holds the default route, via the hi VIP `192.168.71.254`), and
  `192.168.72.15/21` + `2a0e:97c0:4d0:2::1:6` on `lo` VLAN 110. No IP on `untrusted`.
  `l2mtu 9214`, so `hi` carries jumbo (9000) here — `vibe` sits on `hi` because it *can* jumbo,
  unlike `wave` (see its MTU note).
- **Roaming** — 802.11k/v via a `/interface wifi steering` profile (`rrm=yes wnm=yes`,
  `neighbor-group=home-aps`) assigned to `wifi1`/`wifi2`/`wifi3`.
- **Resolver** — the hi VIP `192.168.71.254` / `2a0e:97c0:4d0:1::ffff`.

## wave (Cudy AX3000, OpenWrt)

Single-port AP, so the port is a VLAN **trunk** carrying management + both SSIDs.

### Management addressing

`wave` takes host `.14`, on **`lo` (primary) and `core` (backup)** — deliberately **not** `hi`,
unlike the switches and `vibe`. `hi` is the jumbo (9000) VLAN, but `wave`'s eth0 caps at 2026 (see
MTU note), so there's no reason to put it there; `lo` is 1500 with a proper VRRP VIP for the default
route + resolver, and `core` has no VIP/v6 so it can only be a backup. No IP on `untrusted`. Records
in `dns.nix`:

| Name | VLAN | Address |
|---|---|---|
| `wave-core` | core (native/untagged) | `192.168.64.14/24` — backup, like the switches (no VIP → backup only) |
| `wave` | lo 110 | `192.168.72.14/21`, `2a0e:97c0:4d0:2::1:5` — primary; holds the default route + resolver (lo VIP `192.168.79.254` / `2a0e:97c0:4d0:2::ffff`) |

**Firewall:** management (SSH/LuCI) reachable from `core`/`lo` only; `untrusted` is a separate
zone with `input REJECT` (and `wave` has no IP there) — **no management via the guest VLAN**.

### brian switch port

`wave` hangs off **brian** (UniFi). Its port is a **trunk**: tagged VLAN **110/120** (`lo` + guest),
and **native/untagged = core** (the fabric's management VLAN, carrying `wave-core`). VLAN 100 (`hi`)
is **not** needed here — `wave` isn't on `hi` (see Management addressing). Configure via the UniFi
controller (brian has no CLI); see `home-switches.md`.

### Flashing OpenWrt (Cudy AX3000 / `cudy_ap3000-v1`)

Hardware: MT7981B, 512 MB RAM, 256 MB SPI-NAND, 1× 2.5 GbE (RTL8221B), 2×2 WiFi 6.

> ⚠️ **Serial caveat:** units with a serial starting `2543…` (post ~Nov 2025) use a different flash
> chip and can brick with older firmware. Match firmware to the unit.

OpenWrt can't be flashed directly over stock. Two-stage, via a Cudy **transition** firmware (Cudy
OpenWrt download page / `support@cudy.com`; `warnning.txt` in that bundle has the steps):
1. Stock Cudy UI: update to **≥ 2.4.7** (adds TFTP `recovery.bin` recovery), then flash the Cudy
   **intermediate** firmware (`cudy_ap3000-v1-sysupgrade_*.bin`), "keep settings" **unchecked**.
   It reboots into an OpenWrt-based build at `192.168.1.1` (SSH `root`, empty password).
2. From there, `sysupgrade -n` to vanilla OpenWrt (`…-cudy_ap3000-v1-squashfs-sysupgrade.bin` from
   `downloads.openwrt.org`; this release ships **no** factory image — sysupgrade only).

Stock default (out of box) is a DHCP client falling back to **`192.168.10.254`**; the stock UI is a
customised LuCI (only 80/443, no SSH) with a first-boot "create admin password" wizard — so the
stock-side flashing is done from a browser, not headless.

### On-device config notes

- Package manager is **`apk`** (not `opkg`). WiFi runs **`wpad-mbedtls`** (full — swapped from the
  default `wpad-basic-mbedtls`, which lacks 802.11v). **802.11k + 802.11v** (`ieee80211k` +
  `bss_transition`) are enabled on all SSIDs. ⚠️ Swapping wpad **live** leaves the mac80211 vifs
  stuck in a start→teardown loop (`nl80211 ... No such device`); a `wifi reload`/`network restart`
  won't recover it — **reboot** after `apk add wpad-mbedtls`.
- Radios: `radio0` = 2.4 GHz, `radio1` = 5 GHz (keyed by `band`, don't assume). 5 GHz is pinned to
  **channel 36 / HE160** (any 160 MHz block in IE is DFS; ch36 has the shortest ~60 s CAC).
- Bridge: `br-lan` with `vlan_filtering`, single port `eth0` — tagged `110/120`, untagged/PVID
  VLAN 1 (= native/core). SSIDs attach via `network` = `lo`/`untrusted` (= `br-lan.110`/`.120`).
- Dumb-AP: no DHCP pools, `odhcpd.maindhcp=0`, `delegate=0` on the L3 interfaces.
- **MTU:** all interfaces are **1500**. The `mtk_eth_soc` 2.5 GbE (`eth0`) caps at **2026 bytes**
  (`ip link set eth0 mtu 9000` → `SIOCSIFMTU: Invalid argument`), so `wave` can't join `hi`'s jumbo
  (9000) fabric like `vibe` does — which is precisely **why `wave` is managed on `lo`, not `hi`**
  (see Management addressing). Nothing on `wave` needs > 1500.
- **LuCI:** enabled, login `root` / `admin`. **SSH:** key-only (`PasswordAuth`/`RootPasswordAuth off`).
- `iperf3` installed for throughput testing.

### Access

- SSH: `ssh root@wave` (key-only; `wave`/`wave-core` resolve once `dns.nix` is deployed).
- LuCI: `http://192.168.72.14/` (or `http://wave/`), `root` / `admin`.
