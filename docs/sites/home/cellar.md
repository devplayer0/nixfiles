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
- `spdk-tgt` doesn't restart on deploy (`restartIfChanged = false`): restarting it takes every
  consumer's disk away, so restart it by hand when they can do without.
- `spdk-tgt` is ordered after `lan-hi` is online; the RDMA listener binds the `hi` assignment on
  port 4420. The VM itself is pinned to NUMA node 1 on `palace` and gets SR-IOV VF 0.
- `netdata` (port 19999 allowed in the firewall) and `fstrim`.

## Network assignments

See the consolidated [network assignments](../../networking.md#box-assignments) table (this box: `cellar`).

## Adding an export

Partitions on `NVMeRaid` are ordinary GPT partitions. SPDK's `gpt` module finds them when it
examines the RAID (`bdev_examine` in `spdk.nix`; auto-examine is off) and exposes those whose type
GUID is SPDK's, as `NVMeRaidp<n>`. `p1`–`p3` use the current type GUID,
`6527994e-2c5a-4eec-9613-8f5944074e8b`. Use it for new partitions and leave existing partition
types as they are. SPDK still supports its deprecated type, `7c5222bd-8f5d-4087-9c00-bf9843c7b58c`,
and exposes one fewer block for that type to preserve compatibility with existing on-disk metadata.
[SPDK deprecation notice](https://github.com/spdk/spdk/blob/master/deprecation.md#gpt)

SPDK has no RPC to edit a partition table, so a new partition is written from Linux through ublk,
using `spdk-debug`.
Once examined, the `gpt` module holds an exclusive write claim on `NVMeRaid`, so this can't be done
while the exports are live: every consumer has to be down. Start from a box that stays online
when the exports are offline.

1. Shut down every consumer. Power off `castle` and run
   `doas systemctl stop vm@sfh vm@river` on `palace`. `stream` takes over the router VIPs. On
   `cellar`, verify that `doas spdk-rpc nvmf_subsystem_get_controllers <nqn>` returns `[]` for each
   exported subsystem in the table above.
2. On `cellar`, stop the target and start `spdk-debug` in its place. It runs `spdk_tgt` on a
   config generated from the real one: the same controllers and RAID, but nothing examined (so
   the `gpt` module never claims the RAID), nothing exported, and the RAID exposed through ublk
   (`my.spdk.debug.ublkDisks`):

   ```sh
   doas systemctl stop spdk-tgt
   doas systemd-run --unit=spdk-debug --setenv=PATH=/run/wrappers/bin:/run/current-system/sw/bin "$(command -v spdk-debug)"
   doas spdk-rpc ublk_get_disks                                # NVMeRaid as ublk 1
   lsblk /dev/ublkb1
   ```

   Run plain `doas spdk-debug` instead to keep it in the foreground (`Ctrl-C` stops it).
3. Check the existing table, then add the partition. `sgdisk` isn't installed on `cellar`; a start
   of `0` selects the start of the largest free region. Substitute the new partition number for
   `<n>` and the desired capacity for `<size>`. Verify that all existing entries match the
   expected layout before writing, and check that they remain intact afterward.

   ```sh
   nix shell pkgs#gptfdisk -c doas sgdisk -p /dev/ublkb1
   nix shell pkgs#gptfdisk -c doas sgdisk \
     -n <n>:0:+<size> -t <n>:6527994e-2c5a-4eec-9613-8f5944074e8b /dev/ublkb1
   nix shell pkgs#gptfdisk -c doas sgdisk -p /dev/ublkb1
   ```
4. `doas systemctl stop spdk-debug`, and check `/dev/ublkb1` is gone.
5. If `spdk-debug` fails to start, `journalctl -u spdk-debug` shows why. The same steps can be
   done by hand: `spdk_tgt --wait-for-rpc` under `systemd-run`, then `spdk-rpc bdev_set_options
   --no-auto-examine`, `framework_start_init`, the three `bdev_nvme_attach_controller` calls and
   `bdev_raid_create` exactly as in `spdk.nix`, `ublk_create_target` and
   `ublk_start_disk NVMeRaid 1`.
6. Add an `nvmfBdev` entry for `NVMeRaidp<n>` in `spdk.nix` (its consumer's host NQN and the next
   serial), deploy `cellar` (the unit doesn't restart) and `doas systemctl start spdk-tgt`. Check
   `doas spdk-rpc bdev_get_bdevs` lists the new partition and `doas spdk-rpc nvmf_get_subsystems`
   the new subsystem.
7. Start the consumers again.

If `spdk-tgt` won't start in step 6, the usual cause is a config naming a bdev that doesn't exist.
Switch `cellar` back to its previous generation
(`doas /nix/var/nix/profiles/system-<n>-link/bin/switch-to-configuration switch`), start
`spdk-tgt` and check the existing exports before trying again.

`ublk_drv` is loaded on `cellar`.

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
