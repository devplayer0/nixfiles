# cellar

The home storage server. Exports fast NVMe storage over the network so other
machines (notably `castle`) can boot and run from it.

- **Source:** [`nixos/boxes/home/palace/vms/cellar/`](../../../nixos/boxes/home/palace/vms/cellar)
  (`default.nix`, `spdk.nix`)
- **Host:** VM on `palace` (NVMe drives passed through)
- **Deploy address:** `192.168.68.80`

## Role

- Runs **SPDK** ([`spdk.nix`](../../../nixos/boxes/home/palace/vms/cellar/spdk.nix)) as
  a userspace storage target. The kernel `nvme` driver is blacklisted so SPDK can
  drive the NVMe devices directly (attached by PCI BDF).
- Builds a **RAID0** (`NVMeRaid`) across three NVMe drives, partitioned into three
  namespaces, and exports each as an **NVMe-oF target over RDMA** (port 4420) on
  the high-speed home network — one namespace per consumer:

  | Namespace | NQN | Consumer |
  | --- | --- | --- |
  | `NVMeRaidp1` | `nqn.2016-06.io.spdk:river` | [`river`](river.md) |
  | `NVMeRaidp2` | `nqn.2016-06.io.spdk:castle` | [`castle`](castle.md) |
  | `NVMeRaidp3` | `nqn.2016-06.io.spdk:sfh` | [`sfh`](sfh.md) |

  Each client is pinned by `hostnqn`, so `river`, `castle` and `sfh` all run their
  storage off `cellar` over the network.

## Networking

- Exports on the high-speed home network (`lan-hi` / the `hi` assignment) over
  RDMA; the SPDK target waits for that link to be online before starting.

## Notes

- The `ublk_*` calls in `my.spdk.debugCommands` are **only a debugging script** —
  they let you create a local ublk block device to mount and inspect the RAID on
  `cellar` itself. They are **not** how storage is exported to clients; that is the
  `nvmf` config above.
