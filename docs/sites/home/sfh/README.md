# sfh

"Shill from home" — the NixOS container host for the home site. A VM on `palace` that netboots
from `river` and runs its root off NVMe-oF from `cellar`.

- **Source:** [`nixos/boxes/home/palace/vms/sfh/`](../../../../nixos/boxes/home/palace/vms/sfh)
  (`default.nix`, `containers/`)
- **Host:** VM on `palace`
- **nixpkgs:** `mine`

## Role

- Runs the home NixOS containers via `my.containers.instances` (systemd-nspawn); each container is
  its own `nixos.systems.*` entry rendered through `my.asContainer`.
- **Netboot client** (`my.netboot.client.enable`): the VM has no boot disk — its `netboot` NIC
  on palace's `lan-lo` bridge is matched by a kea client-class on [`river`](../river.md) and
  iPXE-boots from `boot.h.nul.ie`.
- **Root on NVMe-oF**: `my.nvme.boot` connects to `nqn.2016-06.io.spdk:sfh`
  ([`cellar`](../cellar.md), RDMA) from the initrd (`lan-hi` up + `roceBootModules`); `/nix` and
  `/persist` are LVs on that volume. `KeepConfiguration=static` on `lan-hi` protects the
  NVMe-oF address from networkd reconfigures.
- **Frigate footage disk**: palace passes the `hdds/frigate` LVM LV through as a virtio disk;
  sfh mounts it at `/mnt/frigate` (by label) and bind-mounts it into the `hass` container at
  `/var/lib/frigate`.
- USB: two host ports are passed to the VM (qemu flags) for the Zigbee coordinator and webcam used
  by `hass`; the nspawn unit gets `DeviceAllow` for `char-ttyUSB` and `char-video4linux`.

## Network assignments

See the consolidated [network assignments](../../../networking.md#box-assignments) table (this box: `sfh`).

## Networking

| Interface | `palace` attachment | Purpose |
|---|---|---|
| `lan-hi` | `sfh-hi` SR-IOV VF 2 | Box's `hi` assignment and NVMe/RDMA root path; MTU 9000 |
| `ctrs-hi` | `sfh-ctrs` SR-IOV VF 3 | L3-less MACVLAN parent for each container's `host0`; MTU 9000 |
| `ctrs-core` | Virtio via `sfh-core-tap`, `lan-core` and `host-jim` | L3-less MACVLAN parent for UniFi's `lan-core` management attachment |
| `ctrs-lo` | Virtio via `sfh-lo-tap`, `lan-lo` and `host-jim` | L3-less MACVLAN parent for `hass`'s `lan-lo` and the VM's PXE path |

The two VFs separate the box's RDMA root traffic from container `hi` traffic; they do not provide
redundant switch paths. The Virtio attachments reach the `jim`-facing `palace` host bridges. Container
`host0` names are intentionally unchanged.

The per-container MACVLAN wiring lives in `systemd.nspawn.*.networkConfig` in
[`sfh/default.nix`](../../../../nixos/boxes/home/palace/vms/sfh/default.nix). The
[`palace` interface topology](../palace.md#end-to-end-interface-topology) traces these interfaces
back through the VM handoffs to the physical switch connections.

## Containers

| Container | Role |
|---|---|
| [`hass`](containers/hass.md) | Home Assistant + Frigate + MQTT |
| [`unifi`](containers/unifi.md) | UniFi controller |

## Notable config files

- [`nixos/boxes/home/palace/vms/sfh/default.nix`](../../../../nixos/boxes/home/palace/vms/sfh/default.nix) —
  box config: netboot/NVMe-oF boot, container instances, MACVLAN plumbing, Frigate disk.
- [`nixos/boxes/home/palace/vms/sfh/containers/`](../../../../nixos/boxes/home/palace/vms/sfh/containers) —
  the container system definitions.
- [`nixos/boxes/home/palace/vms/default.nix`](../../../../nixos/boxes/home/palace/vms/default.nix) —
  the VM definition on `palace` (VFs, USB passthrough, netboot NIC, `hdds/frigate` disk).
