# portcullis

A bare-metal box destined for Nikhef, intended to take over most of the colony edge
routing currently done by the [`estuary`](estuary.md) VM.

- **Source:** [`nixos/boxes/colony/portcullis/`](../../../nixos/boxes/colony/portcullis)
- **Host:** bare metal
- **nixpkgs:** `mine-stable`

## Hardware

| Component | Inventory |
|---|---|
| Platform | Mini PC (no vendor DMI strings) |
| CPU | Intel N150 (4 cores / 4 threads) |
| Memory | 8 GiB |
| Storage | One 128 GB NVMe SSD (`nvme0n1`), partitioned as a 2 GiB ESP plus an LVM PV holding the `nix` and `persist` volumes |
| Network | Four Intel I226-V 2.5 GbE ports (`et2g5-0`…`et2g5-3`) and one dual-port Intel 82599ES 10 GbE SFP+ card (`et10g-0`, `et10g-1`) |
| Management | JetKVM (HDMI/USB KVM with virtual media) |

The PCIe layout constrains what the cards can reach. The 82599ES sits behind a gen2 x4 link giving
16 Gb/s for **both** its ports together, so one port runs at line rate but the pair is
oversubscribed. The NVMe is on a x1 root port, capped near 7.9 Gb/s regardless of the drive. Each
I226-V has its own x1 link and is not constrained.

## Role

Not yet in service. The eventual job is to be the physical edge for the colony site at Nikhef,
taking over most of what `estuary` does today — WAN termination, firewalling and NAT, BGP for
AS211024 and DNS. Some of that functionality stays on `estuary`, and the surrounding network
topology will change with the move, so the split is not settled yet. Until it is, the config in
this repository covers only what is needed to boot and reach the box.

## Network assignments

`portcullis` has no colony assignments yet — those land alongside the routing config once the
topology is decided. While it is staged at home it holds a single home `hi` assignment, listed in
[`networking.md#box-assignments`](../../networking.md#box-assignments).

## Networking

- The four I226-V ports are named `et2g5-0`…`et2g5-3` and the 82599ES SFP+ ports `et10g-0` /
  `et10g-1`, pinned by permanent MAC address in `.link` files.
- Bootstrap: a single `.network` matches every `et2g5-*` port and takes DHCP on the home `lo` VLAN,
  so whichever port happens to be patched in brings the box up. `wait-online.anyInterface` keeps
  boot from blocking on the unpatched ports.
- kea registers the DHCP hostname, so while staged the box also answers to `portcullis.dyn.h.nul.ie`.
- `my.deploy.node.hostname` is the `hi` address, taken from the assignment rather than written out,
  since there is no colony FQDN for the box yet.

### 10G to the home `hi` VLAN

`et10g-0` runs over fibre to [`fergal`](fergal.md), which uplinks to jim's `sfp-spare` port. That
uplink is untagged VLAN 1, so `hi` is carried tagged on a `lan-hi` VLAN interface rather than on the
port itself; the physical link takes the `hi` jumbo MTU so the whole path is consistent with the
rest of the VLAN. `lan-hi` carries the static assignment, resolves through the router VIPs like
every other `hi` client, and its gateway route outranks the DHCP default, so the 10G path is
preferred while the 2.5G one stays as a fallback.

Both jim and `fergal` tag `hi` and `lo` along that path. It exists only while the box is staged at
home — `fergal` goes to Nikhef with it.

The other SFP+ port, `et10g-1`, is unused.

### Interface tuning

Every port takes router-sized 4096-entry rings rather than the driver defaults, matching the other
routers here, and enables `GenericReceiveOffloadUDPForwarding` so GRO batching survives forwarding
once the box carries UDP-encapsulated traffic. Both are `.link` settings, so they apply on the next
device event rather than at switch time — a reboot is the reliable way to land a change to them.

Interrupt coalescing is deliberately left alone. `igc` reports `rx-usecs` 3 and `ixgbe` reports 1,
which are the drivers' markers for dynamic ITR rather than literal microseconds; writing a
plausible-looking value there replaces adaptive moderation with a fixed one.

### I226-V erratum

The I226-V link-drop erratum is driven by PCIe ASPM, Energy Efficient Ethernet and stale NIC
firmware. ASPM, the dominant cause, is off across the whole box for the reason in
[Power](#power) below. EEE is held off by a udev rule invoking `ethtool`, as `systemd.link` has no
knob for it. `igc` already leaves EEE off on these ports, so the rule pins a driver default rather
than correcting one, and keeps it from drifting on a kernel bump. Firmware is the remaining item:
the ports report NVM `2.13` (EEPROM version word `0x2013`, which `igc` prints as the `2013` in
`ethtool -i`), behind the `2.29`/`2.32` images that circulate. Intel does not publish the I226-V
NVM image, so updating means third-party firmware and is best attempted while the box is at home
and the JetKVM is attached.

## Power

The SoC side is already at its floor and needs no tuning: the package draws around 0.75 W idle with
cores in C10 essentially all the time, under `intel_pstate` on the `powersave` governor.

Platform idle is capped instead, and deliberately left that way. The ACPI FADT declares that the
system does not support PCIe ASPM, so the OS defers to firmware, every root port advertises ASPM as
unsupported and every endpoint sits with it disabled. Deep package C-states need every PCIe link in
L1, so the package never leaves C3. `pcie_aspm=force` is the usual answer and is **not** used here:
the 82599ES advertises only L0s with an unlimited exit latency, so no amount of forcing reaches the
deep states while that card is fitted, and the only links it would actually change are the four
I226-V ones — the exact configuration behind the erratum above. Recovering that power is a firmware
question for the mini PC, and only worthwhile once the 82599ES is gone.

`iommu=pt` puts host devices in passthrough so the forwarding path does not pay DMA translation,
while leaving the IOMMU available.

## Storage

A single NVMe SSD, following the usual tmpfs-root layout: a 2 GiB ESP at `/boot`, then one LVM PV
in volume group `main` carrying `portcullis-nix` (48 GiB, `/nix`) and `portcullis-persist` (the
remainder, `/persist`).

## Secrets

`my.secrets.key` is the SSH host key adopted from the installer session at install time (seeded onto
the persist volume before first boot), so secrets could be encrypted for the box without waiting for
it to come up. The box declares nothing of its own yet — only the default `user-passwd.txt` that
`my.user` brings in.

## Notable config files

- [`nixos/boxes/colony/portcullis/default.nix`](../../../nixos/boxes/colony/portcullis/default.nix) — hardware, filesystems and bootstrap networking.
