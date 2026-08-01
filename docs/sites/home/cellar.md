# cellar

The home storage target. A VM on `palace` that drives three passed-through NVMe disks with SPDK
and exports them over NVMe-oF/RDMA — `river`, `sfh` and `castle` all run their root storage off
it.

- **Source:** [`nixos/boxes/home/palace/vms/cellar/`](../../../nixos/boxes/home/palace/vms/cellar)
  (`default.nix`, `spdk.nix`)
- **Host:** VM on `palace`
- **nixpkgs:** `mine`

## Role

- Runs an **SPDK userspace target** (`my.spdk`, [`spdk.nix`](../../../nixos/boxes/home/palace/vms/cellar/spdk.nix)):
  the kernel `nvme` driver is blacklisted so SPDK can claim the three NVMe controllers directly
  (host BDFs `41:00.0`–`43:00.0`, attached in the guest as `02:00.0`–`04:00.0`).
- Builds a **RAID-0** (`NVMeRaid`) across the three drives and exports one
  partition per consumer as an **NVMe-oF subsystem over RDMA** (port 4420) on the `hi` network:

  | Bdev | NQN | Consumer |
  |---|---|---|
  | `NVMeRaidp1` | `nqn.2016-06.io.spdk:river` | [`river`](river.md) |
  | `NVMeRaidp2` | `nqn.2016-06.io.spdk:castle` | [`castle`](castle.md) |
  | `NVMeRaidp3` | `nqn.2016-06.io.spdk:sfh` | [`sfh`](sfh/README.md) |

  Each subsystem is pinned to its consumer's `hostnqn` (the `my.nvme.uuid` on the client side).
- `spdk-tgt` is ordered after `lan-hi` is online; the RDMA listener binds the `hi` assignment on
  port 4420. The VM itself is pinned to NUMA node 1 on `palace` and gets SR-IOV VF 0.
- `netdata` (port 19999 allowed in the firewall) and `fstrim`.

## Network assignments

See the consolidated [network assignments](../../networking.md#box-assignments) table (this box: `cellar`).

## Notes

- The `ublk_*` calls in `my.spdk.debugCommands` are only a debugging aid — they create a local
  ublk device so the RAID can be mounted and inspected on `cellar` itself. Client exports are the
  `nvmf` subsystems above.

## Notable config files

- [`nixos/boxes/home/palace/vms/cellar/default.nix`](../../../nixos/boxes/home/palace/vms/cellar/default.nix) —
  box config (assignment, networking, netdata).
- [`nixos/boxes/home/palace/vms/cellar/spdk.nix`](../../../nixos/boxes/home/palace/vms/cellar/spdk.nix) —
  SPDK target: RAID-0, NVMe-oF/RDMA subsystems.
- [`nixos/boxes/home/palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix) —
  the VM definition on `palace` (VF 0, NVMe passthrough, NUMA pinning).
