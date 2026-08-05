# Home 5G WWAN modem

Reference for the Quectel **RM500U-EA** USB 5G modem, bought to eventually replace `stream`'s
Virgin Media cable WAN ([stream.md](stream.md)). Like the switches ([switches.md](switches.md)) and
the APs ([aps.md](aps.md)), it is **not** managed by this flake: the module's own settings live in
its NVRAM and are applied out-of-band over AT, and nothing in the repo references it yet.

As of 2026-08-05 it has only been bench-tested on `tower`; `stream` is untouched. The notes below
are the working knowledge from that session — what the module needs in order to connect at all, and
what is still unresolved.

## The hardware

| | |
|---|---|
| Model | Quectel **RM500U-EA** |
| Platform | UNISOC-based (not Qualcomm) — its AT set is the `AT+QCFG`/`AT+QNETDEVCTL` router-firmware family, not the QMI one |
| USB | `2c7c:0900`, SuperSpeed (USB 3.1) |
| Firmware | `RM500UEAAAR03A13M2G` |
| SIM | **GoMo**, which rides eir's network (MCC/MNC **272-03**, AS**15751** Meteor Mobile) |

The SIM's **PIN lock has been disabled** on the SIM itself, so no PIN needs to be entered at boot
and no age secret is required for it. Card identifiers and the PIN are deliberately not recorded
here; read them from the modem with `mmcli` if needed.

## The module must be in MBIM mode

This is the single most important setting. The module ships in **NCM** mode (`AT+QCFG="usbnet",5`),
and in that mode it does not work:

- The PDP context comes up correctly — `AT+CGPADDR` reports a real address and `AT+CGCONTRDP`
  reports the APN, DNS servers and prefix — but the `cdc_ncm` interface **never raises carrier**, so
  no traffic can leave the box. No combination of `AT+QNETDEVCTL` modes (the `(0-3)` operations,
  per profile) changed that.
- ModemManager also mis-reports the module's capability as `gsm-umts` only, and cannot read signal
  quality (it sits at 0% while the radio is registered and attached).

Switching to **MBIM** fixes both:

```
AT+QCFG="usbnet",2
AT+CFUN=1,1          # reset so the new USB composition takes effect
```

It then enumerates as `cdc_mbim` with `/dev/cdc-wdm0` and a `wwp*` interface, ModemManager reports
`gsm-umts, lte, 5gnr`, signal quality works, and carrier follows the bearer. The other `usbnet`
values the module advertises are `(1,2,3,5,11,13,15)` — `1` ECM, `2` MBIM, `3` RNDIS, `5` NCM.

To reach the AT ports (`ttyUSB2` and `ttyUSB3` are the AT ones; ModemManager claims them, so stop it
first), any serial terminal works — `minicom -D /dev/ttyUSB2`, or a raw `stty`/`exec` pair on the
device node.

### Router-mode features are not in use

The firmware is the router variant: it can do its own NAT (`AT+QCFG="nat"`) and hand the host a
lease off a private LAN prefix (`AT+QCFG="lanip"`, default `192.168.42.0/24`). It is currently in
bridge mode (`nat=0`) so the host gets the real WAN address. NAT mode was not needed once MBIM
worked, and would mean double NAT.

## Connecting: the APN must be the network-expanded form

The documented consumer APNs (`gomo.ie`, `data.myeirmobile.ie`) **fail**. The connect only succeeds
with the fully expanded name the network itself uses, and only as **IPv4**:

```
mmcli -m <n> --simple-connect="apn=data.myeirmobile.ie.mnc003.mcc272.gprs,ip-type=ipv4"
```

The module has `AT+QCFG="autoapn",1`, so it selects an APN by itself during attach and brings up an
initial EPS bearer regardless. That bearer is where the expanded name comes from: list the modem's
bearers and read the one whose type is `default-attach`.

```
mmcli -m <n>          # note the bearer paths and the initial bearer path
mmcli -b <n>          # the default-attach bearer carries the real APN
```

Failure modes are worth distinguishing, since they look similar from `mmcli`:

| Symptom | Meaning |
|---|---|
| `MBIM status error: Failure`, immediate | The APN reached the network and was rejected — usually the wrong APN string |
| `Network timeout`, after a long wait | The APN never resolved to anything; wrong name entirely |
| `No valid data port found` | Already connected — the single data port is in use by an existing bearer |

## Bench result on tower

Measured 2026-08-05 on `tower`, indoors, with **no external antennas** and a weak signal
(RSSI around −85 dBm):

| | |
|---|---|
| Access technology | `lte, 5gnr` — 5G **NSA** |
| Throughput | ~64 Mbit/s down, ~26 Mbit/s up |
| Latency | ~76 ms to `1.1.1.1` |
| Bearer-negotiated rates | 150 Mbit/s down, 50 Mbit/s up |

Treat the throughput as a floor, not a characterisation — antennas and siting were both worst-case.

## The address is CGNAT, and the prefix length is a trap

Two separate consequences of how the bearer addresses the host.

### No public IP

The bearer address is in `100.64.0.0/10` and egress is carrier-NAT'd (`*.cgn1.srl.meteor.ie`,
AS15751). There is **no inbound reachability and no public address**. `stream` currently takes a
*public* DHCP lease on `wan` and publishes it — see [stream.md](stream.md#wan-virgin-media-dhcp),
which also drives `my.homeRouter.dns.wanSkipBroadcasts`. Replacing that WAN with this SIM therefore
drops port forwards, inbound WireGuard and anything resolving to `stream`'s WAN address. Making
this a real WAN needs either a public/static IP from the carrier, or `stream`'s inbound
reachability moved onto the AS211024 mesh or a tunnel from `britway`
([networking.md](../../networking.md)).

### The bearer reports a /8

ModemManager reports the address with a **`/8` prefix**, i.e. `100.0.0.0/8`. Configuring that
literally would install a route covering **Tailscale's `100.64.0.0/10`** and break it. Any
configuration for this modem must add the address as a `/32` with an explicit on-link route to the
gateway, and never use the bearer's own prefix length.

For a throwaway test that cannot disturb the box, put the address and default route in their own
routing table behind an `ip rule` matching the source address, and drive traffic onto it with
`ping -I <addr>` / `curl --interface <addr>`.

## Still open

- **IPv6.** GoMo is expected to provide it, but `ip-type=ipv4v6` fails to connect and only
  `ip-type=ipv4` works. In NCM mode the module *did* report an IPv6 address and IPv6 DNS servers
  (`2001:bb0::11`/`::12`) on the context, so the network clearly offers it — this looks like an APN
  or MBIM-session problem rather than a carrier one. Worth retrying with a separate IPv6-only
  context, or with the initial EPS bearer settings pinned via
  `mmcli --3gpp-set-initial-eps-bearer-settings`.
- **A public or static IP** from GoMo/eir, without which this cannot replace `stream`'s WAN
  unchanged (see above).
- **Antenna siting**, and whether 5G **SA** is reachable rather than the NSA seen so far.
- **Flake integration** — nothing exists yet. It would need the MBIM interface configured under
  `stream`'s networkd, a `wan-online.target` mechanism equivalent to the current DHCP-route gate,
  and a decision on whether ModemManager or a plain `mbimcli` connect script drives the bearer.
