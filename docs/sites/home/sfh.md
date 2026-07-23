# sfh

"Services for home" — the NixOS container host for the home site. A VM on `palace` that netboots
from `river` and runs its root off NVMe-oF from `cellar`.

- **Source:** [`nixos/boxes/home/palace/vms/sfh/`](../../../nixos/boxes/home/palace/vms/sfh)
  (`default.nix`, `containers/`)
- **Host:** VM on `palace`

## Role

- Runs the home NixOS containers via `my.containers.instances` (systemd-nspawn); each container is
  its own `nixos.systems.*` entry rendered through `my.asContainer`.
- **Netboot client** (`my.netboot.client.enable`): the VM has no boot disk — its `netboot` NIC
  (MAC `52:54:00:a5:7e:93`, on palace's `lan-lo` bridge, `bootindex=1`) is matched by a kea
  client-class on [`river`](river.md) and iPXE-boots from `boot.h.nul.ie`.
- **Root on NVMe-oF**: `my.nvme.boot` connects to `nqn.2016-06.io.spdk:sfh` at `192.168.68.80`
  ([`cellar`](cellar.md), RDMA) from the initrd (`lan-hi` up + `roceBootModules`); `/nix` and
  `/persist` are LVs on that volume. `KeepConfiguration=static` on `lan-hi` protects the
  NVMe-oF address from networkd reconfigures.
- **Frigate footage disk**: palace passes the `hdds/frigate` LVM LV through as a virtio disk;
  sfh mounts it at `/mnt/frigate` (by label) and bind-mounts it into the `hass` container at
  `/var/lib/frigate`.
- USB: two host ports are passed to the VM (qemu flags) for the Zigbee coordinator and webcam used
  by `hass`; the nspawn unit gets `DeviceAllow` for `char-ttyUSB` and `char-video4linux`.

## Network assignments

<!-- assignments: sfh -->
<!-- assignments-start -->
| Name | Assignment | IPv4 | IPv6 | Domain | Notes |
|---|---|---|---|---|---|
| sfh | hi | `192.168.68.81/22 gw 192.168.71.254` | `2a0e:97c0:4d0:1::4:2/64` | h.nul.ie |  |
<!-- assignments-end -->

## Networking

Four NICs, all MTU 9000 where jumbo-capable:

- `lan-hi` — SR-IOV VF 2, the box's own `hi` assignment (`192.168.68.81`).
- `lan-hi-ctrs` — SR-IOV VF 3, no L3: the MACVLAN parent for the containers' `hi` legs
  (`host0` inside each container).
- `lan-core-ctrs` / `lan-lo-ctrs` — virtio NICs (bridged to palace's `lan-core` / `lan-lo`), no
  L3: MACVLAN parents for containers that need a `core` or `lo` leg.

The per-container MACVLAN wiring lives in `systemd.nspawn.*.networkConfig` in
[`sfh/default.nix`](../../../nixos/boxes/home/palace/vms/sfh/default.nix).

## Containers

| Container | Role | Page |
|---|---|---|
| `hass` | Home Assistant + Frigate + MQTT | [sfh/containers/hass.md](sfh/containers/hass.md) |
| `unifi` | UniFi controller | [sfh/containers/unifi.md](sfh/containers/unifi.md) |

## Notable config files

- [`nixos/boxes/home/palace/vms/sfh/default.nix`](../../../nixos/boxes/home/palace/vms/sfh/default.nix) —
  box config: netboot/NVMe-oF boot, container instances, MACVLAN plumbing, Frigate disk.
- [`nixos/boxes/home/palace/vms/sfh/containers/`](../../../nixos/boxes/home/palace/vms/sfh/containers) —
  the container system definitions.
- [`nixos/boxes/home/palace/vms/default.nix`](../../../nixos/boxes/home/palace/vms/default.nix) —
  the VM definition on `palace` (VFs, USB passthrough, netboot NIC, `hdds/frigate` disk).
