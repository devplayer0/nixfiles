# Router failover validation

Failure-scenario checks for the deployed home router pair. The design lives in
[Router HA](../../networking.md#router-ha), the physical paths in [switches.md](switches.md),
and the host/VF layout in [palace.md](palace.md) and [river.md](river.md).

## Validated scenarios

These checks were performed on 2026-11-15. WAN and ONT probes check Ethernet path availability;
reads from `river`'s root LV and probes over `rdma-hi` check its separate storage path.

| Scenario | Test | Validated behavior |
|---|---|---|
| Router startup | Boot both routers | Kea starts without retries; the configured bridge MAC, ARP policy and administrative RSTP costs are applied |
| Primary router offline | Reboot its host | `stream` takes over both IPv4 and IPv6 VIPs, then returns to standby when `river` recovers |
| Preferred guest port down | Disable `river`'s `lan-dave`, then restore it | `lan-jim` becomes root/forwarding; WAN, ONT and 9000-byte RDMA pings pass while direct root-LV reads continue for 20 seconds |
| Backup guest port down | Disable `river`'s `lan-jim`, then restore it | `lan-dave` stays root/forwarding; WAN, ONT, jumbo RDMA and root-LV read checks pass |
| Physical `palace` attachment lost | Disable `dave`'s `palace` port for 30 seconds with automatic restoration | `lan-dave` loses carrier and `lan-jim` becomes root/forwarding; forced-link storage VFs retain local RDMA and root-LV reads succeed |
| Whole `dave` outage | Reboot the switch | `jim` becomes root and forwards on `brian-downlink`; Digiweb WAN and ONT access use `jim`–`brian` while local RDMA reads continue |
| Whole `jim` outage | Reboot the switch | `river` continues using `dave`; WAN, ONT and root-storage read probes succeed |
| Restoration | Restore each failed attachment or switch | The normal RSTP preferences return and `palace` is reachable on `hi` again |

Brief WAN/ONT probe losses occur during the tested `dave` tree transitions; subsequent probes
succeed on the backup tree and after restoration. The monitors recorded no storage-read
failures or matched kernel NVMe errors. The whole-switch test demonstrates the backup WAN path
without relying on the direct `jim`–`dave` trunk.

## Test limits

The storage checks exercise reads, not write integrity or long-duration endurance. They validate
local VF-to-VF RDMA during physical carrier loss, not failure of the ConnectX-4 itself. Storage
still depends on the adapter, `palace` and `cellar`; see [river's storage](river.md#storage).

`brian`'s live RSTP port state was not captured during the outage tests. Its backup
connection is validated by successful WAN and ONT traffic while `dave` is offline.

Disabling only the guest trunk VF while the host PF remains healthy is an artificial fault:
`palace`'s `hi` return traffic can still target that local VF's MAC and become unreachable through
`river`. During physical carrier loss, external `hi` access to the host and its guests is also
unavailable. `palace` remains accessible on `core` through a jump connection from `stream`;
direct routed management access depends on a working return route.

## Repeating the checks

Perform maintenance from a box independent of `palace`, such as `tower`. Before interrupting
`palace` or `dave`, power `castle` off cleanly: its NVMe-oF root depends on `cellar` and `dave`.
Keep a known-working boot entry and working JetKVM video and keyboard access.

1. Check boot defaults, system profiles, switch VLAN membership and spanning-tree state. When
   changing host and guest networking together, stage matching configurations with `deploy --boot`.
2. Verify VF isolation, VLAN/trust/carrier policies, MTUs, the RoCE GID and the mounted NVMe
   subsystem before injecting a fault.
3. Arrange independent automatic restoration before disabling an interface or switch port.
   Run probes and storage reads in a service that survives loss of the SSH connection; bound
   remote commands so a path change cannot leave a check waiting indefinitely.
4. Inject one fault at a time. Monitor root/alternate port roles, native `core`, client VLANs,
   ONT access, PPPoE, DNS through the floating VIPs and storage I/O. Capture BPDUs when changing
   the topology and watch for returned own-source packets or MAC flapping.
5. Restore the path and verify the normal RSTP roles, VIP ownership, services and management
   access before testing another fault.

Switch changes require confirmation; see [switches.md](switches.md#accessing-the-switches).
