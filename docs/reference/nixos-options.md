# NixOS module options (`my.*`)

> **Generated** from the module option descriptions by `nix run .#update-docs-options`;
> CI keeps it current. The source of truth is the `mkOpt'` / `mkBoolOpt'` declarations in
> `nixos/modules/` — edit those, not this file. For what each module is *for*, see the
> [shared-modules overview](../architecture.md#shared-modules).

## `borgthin` — [`nixos/modules/borgthin.nix`](../../nixos/modules/borgthin.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.borgthin.enable` | boolean | `false` | Whether to enable borgthin jobs |
| `my.borgthin.jobs` | attribute set of (submodule) | `{ }` | borgthin jobs |
| `my.borgthin.jobs.<name>.archivePrefix` | string | `"${config.networking.hostName}-${name}-"` | Prefix to start new archives with |
| `my.borgthin.jobs.<name>.compression` | string | `"zstd,3"` | Compression options |
| `my.borgthin.jobs.<name>.dateFormat` | string | `"+%Y-%m-%dT%H:%M:%S"` | Format passed to the date command |
| `my.borgthin.jobs.<name>.environment` | attribute set of string | `{ }` | Extra environment variables to pass to borg |
| `my.borgthin.jobs.<name>.extraArgs` | list of string | `[ "--iec" ]` | Extra args to pass to all borg commands |
| `my.borgthin.jobs.<name>.extraCreateArgs` | list of string | `[ ]` | Extra args to pass to tcreate command |
| `my.borgthin.jobs.<name>.lvs` | list of string | `null` | Thin LVs to backup (vg/lv format) |
| `my.borgthin.jobs.<name>.passFile` | null or string | `null` | Path to file containing passphrase |
| `my.borgthin.jobs.<name>.prune.keep` | attribute set of (signed integer or string) | `{ }` | Borg pruning params |
| `my.borgthin.jobs.<name>.prune.pattern` | string | `"sh:${config.archivePrefix}*"` | Borg pattern to select archives for pruning |
| `my.borgthin.jobs.<name>.repo` | string | `null` | borg repository URL |
| `my.borgthin.jobs.<name>.timer.at` | string or list of string | `"5:00"` | systemd calendar time(s) to run backup at |
| `my.borgthin.jobs.<name>.timer.persistent` | boolean | `false` | Persistent systemd timer |
| `my.borgthin.lvmPackage` | package | `<derivation lvm2-2.03.41>` | Packge containing LVM tools |
| `my.borgthin.package` | package | `inputs.borgthin.packages.${system}.borgthin` | borgthin package |
| `my.borgthin.thinToolsPackage` | package | `<derivation thin-provisioning-tools-1.3.2>` | Package containing thin-provisioning-tools |

## `build` — [`nixos/modules/build.nix`](../../nixos/modules/build.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.build.allHardware` | boolean | `false` | Whether to enable a lot of firmware and kernel modules for a wide range of hardware.Only applies to some build targets. |
| `my.build.isDevVM` | boolean | `false` | Whether the system is a development VM. |
| `my.buildAs` | open submodule of lazy attribute set of unspecified value | `{ }` | Attribute set of derivations used to set up the system. |

## `common` — [`nixos/modules/common.nix`](../../nixos/modules/common.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.tmproot.persistence.config.users` | attribute set of (submodule) | `{ }` | A set of user submodules listing the files and directories to link to their respective user's home directories. Each attribute name should be the name of the user. For detailed usage, check the [documentation](https://github.com/nix-community/impermanence). |

## `containers` — [`nixos/modules/containers.nix`](../../nixos/modules/containers.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.containers.instances` | attribute set of (submodule) | `{ }` | Individual containers. |
| `my.containers.instances.<name>.autoStart` | boolean | `true` | Whether to start the container automatically at boot. |
| `my.containers.instances.<name>.bindMounts` | attribute set of (submodule) | `{ }` | An extra list of directories that is bound to the container. |
| `my.containers.instances.<name>.bindMounts.<name>.hostPath` | null or string | `"‹name›"` | Location of the host path to be mounted. |
| `my.containers.instances.<name>.bindMounts.<name>.mountPoint` | string | `"‹name›"` | Mount point on the container file system. |
| `my.containers.instances.<name>.bindMounts.<name>.readOnly` | boolean | `true` | Determine whether the mounted path will be accessed in read-only mode. |
| `my.containers.instances.<name>.containerSystem` | absolute path | `"/nix/var/nix/profiles/system"` | Path to NixOS system configuration from within container. |
| `my.containers.instances.<name>.hotReload` | boolean | `true` | Whether to apply new configuration by running `switch-to-configuration` instead of rebooting the container. |
| `my.containers.instances.<name>.networking.bridge` | null or string | `null` | Network bridge to connect to. |
| `my.containers.instances.<name>.networking.macVLAN` | null or string | `null` | Network interface to make MACVLAN interface from. |
| `my.containers.instances.<name>.system` | absolute path | `"/nix/var/nix/profiles/per-container/‹name›/system"` | Path to NixOS system configuration. |
| `my.containers.persistDir` | string | `"/persist/containers"` | Where to store container persistence data. |

## `deploy-rs` — [`nixos/modules/deploy-rs.nix`](../../nixos/modules/deploy-rs.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.deploy.authorizedKeys.keyFiles` | list of absolute path | `[ .keys/deploy.pub ]` | SSH public key files to add to the default deployment user. |
| `my.deploy.authorizedKeys.keys` | list of (optionally newline-terminated) single-line string | `[ ]` | SSH public keys to add to the default deployment user. |
| `my.deploy.enable` | boolean | `true` | Whether to expose deploy-rs configuration for this system. |
| `my.deploy.generate.containers.enable` | boolean | `true` | Whether to generate deploy-rs profiles for this system's containers. |
| `my.deploy.generate.containers.keepGenerations` | unsigned integer, meaning >=0 | `10` | Number of generations to keep when cleaning up old deployments (0 to disable deletion on deployment). |
| `my.deploy.generate.system.enable` | boolean | `true` | Whether to generate a deploy-rs profile for this system's config. |
| `my.deploy.generate.system.keepGenerations` | unsigned integer, meaning >=0 | `10` | Number of generations to keep when cleaning up old deployments (0 to disable deletion on deployment). |
| `my.deploy.generate.system.mode` | string | `"switch"` | switch-to-configuration mode. |
| `my.deploy.node` | submodule | `{ }` | deploy-rs node configuration. |
| `my.deploy.node.autoRollback` | null or boolean | `null` | Whether to roll back the profile if activation fails. |
| `my.deploy.node.confirmTimeout` | null or 16 bit unsigned integer; between 0 and 65535 (both inclusive) | `null` | Timeout for confirming activation succeeded. |
| `my.deploy.node.fastConnection` | null or boolean | `null` | Whether to copy the whole closure instead of using substitution. |
| `my.deploy.node.hostname` | string | `""` | Hostname deploy-rs will connect to. |
| `my.deploy.node.magicRollback` | null or boolean | `null` | Whether to roll back the profile if connectivity to the deployer is lost. |
| `my.deploy.node.profiles` | attribute set of (submodule) | `{ }` | Profiles to deploy. |
| `my.deploy.node.profiles.<name>.autoRollback` | null or boolean | `null` | Whether to roll back the profile if activation fails. |
| `my.deploy.node.profiles.<name>.confirmTimeout` | null or 16 bit unsigned integer; between 0 and 65535 (both inclusive) | `null` | Timeout for confirming activation succeeded. |
| `my.deploy.node.profiles.<name>.fastConnection` | null or boolean | `null` | Whether to copy the whole closure instead of using substitution. |
| `my.deploy.node.profiles.<name>.magicRollback` | null or boolean | `null` | Whether to roll back the profile if connectivity to the deployer is lost. |
| `my.deploy.node.profiles.<name>.path` | package | `""` | Derivation to build (should include activation script). |
| `my.deploy.node.profiles.<name>.profilePath` | null or string | `null` | Path to profile location |
| `my.deploy.node.profiles.<name>.sshOpts` | list of string | `[ ]` | Options deploy-rs will pass to ssh. Note: overriding at a lower level _merges_ options. |
| `my.deploy.node.profiles.<name>.sshUser` | null or string | `null` | Username deploy-rs will deploy with. |
| `my.deploy.node.profiles.<name>.sudo` | null or string | `null` | Command to elevate privileges with (used if the deployment user != profile user). |
| `my.deploy.node.profiles.<name>.tempPath` | null or string | `null` | Path that deploy-rs will use for temporary files. |
| `my.deploy.node.profiles.<name>.user` | null or string | `null` | Username deploy-rs will deploy with. |
| `my.deploy.node.profilesOrder` | null or (list of string) | `null` | Order to deploy profiles in (remainder will be deployed in arbitrary order). |
| `my.deploy.node.sshOpts` | list of string | `[ ]` | Options deploy-rs will pass to ssh. Note: overriding at a lower level _merges_ options. |
| `my.deploy.node.sshUser` | null or string | `null` | Username deploy-rs will deploy with. |
| `my.deploy.node.sudo` | null or string | `null` | Command to elevate privileges with (used if the deployment user != profile user). |
| `my.deploy.node.tempPath` | null or string | `null` | Path that deploy-rs will use for temporary files. |
| `my.deploy.node.user` | null or string | `null` | Username deploy-rs will deploy with. |

## `dynamic-motd` — [`nixos/modules/dynamic-motd.nix`](../../nixos/modules/dynamic-motd.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.dynamic-motd.enable` | boolean | `true` | Whether to enable the dynamic message of the day PAM module. |
| `my.dynamic-motd.script` | null or strings concatenated with "\n" | `null` | Script that generates message of the day. |
| `my.dynamic-motd.services` | list of string | `[ "login" "sshd" ]` | PAM services to enable the dynamic message of the day module for. |

## `firewall` — [`nixos/modules/firewall.nix`](../../nixos/modules/firewall.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.firewall.enable` | boolean | `true` | Whether to enable the nftables-based firewall. |
| `my.firewall.extraRules` | strings concatenated with "\n" | `""` | Arbitrary additional nftables rules. |
| `my.firewall.nat.enable` | boolean | `true` | Whether to enable IP forwarding and NAT. |
| `my.firewall.nat.externalInterface` | null or string | `null` | The name of the external network interface. |
| `my.firewall.nat.forwardPorts` | (list of (submodule)) or attribute set of list of (submodule) | `[ ]` | IPv4 port forwards |
| `my.firewall.tcp.allowed` | list of (16 bit unsigned integer; between 0 and 65535 (both inclusive) or string) | `[ ]` | TCP ports to open. |
| `my.firewall.trustedInterfaces` | list of string | `[ ]` | Traffic coming in from these interfaces will be accepted unconditionally. Traffic from the loopback (lo) interface will always be accepted. |
| `my.firewall.udp.allowTraceroute` | boolean | `true` | Whethor or not to add a rule to accept UDP traceroute packets. |
| `my.firewall.udp.allowed` | list of (16 bit unsigned integer; between 0 and 65535 (both inclusive) or string) | `[ ]` | UDP ports to open. |

## `gui` — [`nixos/modules/gui`](../../nixos/modules/gui)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.gui.enable` | boolean | `true` | Whether to enable GUI system options. |

## `l2mesh` — [`nixos/modules/l2mesh.nix`](../../nixos/modules/l2mesh.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.vpns.l2.pskFiles` | attribute set of string | `{ }` | PSK files for secured meshes. |

## `librespeed` — [`nixos/modules/librespeed`](../../nixos/modules/librespeed)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.librespeed.backend.enable` | boolean | `false` | Whether to enable librespeed backend. |
| `my.librespeed.backend.extraSettingsFile` | null or string | `null` | Extra settings file. |
| `my.librespeed.backend.settings` | attribute set of unspecified value | `{ }` | Backend settings. |
| `my.librespeed.frontend.servers` | list of attribute set of unspecified value | `{ }` | Server configs. |
| `my.librespeed.frontend.webroot` | package | — | Frontend webroot. |

## `netboot` — [`nixos/modules/netboot`](../../nixos/modules/netboot)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.netboot.client.configurationLimit` | unsigned integer, meaning >=0 | `10` | Max generations to show in boot menu. |
| `my.netboot.client.enable` | boolean | `false` | Whether network booting should be enabled. |
| `my.netboot.server.allowedPrefixes` | list of string | `null` | Prefixes clients should be allowed to connect from (NFS). |
| `my.netboot.server.enable` | boolean | `false` | Whether a netboot server should be enabled. |
| `my.netboot.server.host` | string | `config.networking.fqdn` | Hostname clients should connect to over HTTP / NFS. |
| `my.netboot.server.installer.storeSize` | string | `"16GiB"` | Total allowed writable size of store. |
| `my.netboot.server.instances` | list of string | `[ ]` | Systems to hold boot files for. |
| `my.netboot.server.ip` | string | `null` | IP clients should connect to via TFTP. |

## `nginx-sso` — [`nixos/modules/nginx-sso.nix`](../../nixos/modules/nginx-sso.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.nginx-sso.configuration` | attribute set of unspecified value | `{ }` | nginx-sso configuration. |
| `my.nginx-sso.enable` | boolean | `false` | Whether to enable custom nginx-sso. |
| `my.nginx-sso.extraConfigFile` | null or string | `null` | Path to configuration (e.g. for secrets). |
| `my.nginx-sso.includes.baseURL` | string | `null` | Base URL for redirects. |
| `my.nginx-sso.includes.endpoint` | string | `"http://localhost:8082"` | Upstream for proxied auth requests. |
| `my.nginx-sso.includes.instances` | attribute set of (submodule) | `{ }` | nginx includes instances. |
| `my.nginx-sso.includes.instances.<name>.auth.path` | string | `"/sso-auth"` | HTTP path for SSO auth. |
| `my.nginx-sso.includes.instances.<name>.auth.redirect` | string | `"$scheme://$http_host$request_uri"` | URL to redirect to upon successful login. |
| `my.nginx-sso.includes.instances.<name>.logout.path` | string | `"/sso-logout"` | HTTP path for SSO logout. |
| `my.nginx-sso.includes.instances.<name>.logout.redirect` | string | `"$scheme://$http_host/"` | URL to redirect to upon successful logout. |
| `my.nginx-sso.package` | package | `<derivation nginx-sso-0.27.8>` | nginx-sso package to use. |

## `nvme` — [`nixos/modules/nvme`](../../nixos/modules/nvme)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.nvme.boot.address` | string | `null` | Address of NVMe-oF target. |
| `my.nvme.boot.nqn` | null or string | `null` | NQN to connect to on boot |
| `my.nvme.uuid` | null or string | `null` | NVMe host ID |

## `pdns` — [`nixos/modules/pdns.nix`](../../nixos/modules/pdns.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.pdns.auth.bind.file-records.sshKey` | null or string | `null` | SSH public key for file record update user. |
| `my.pdns.auth.bind.options.also-notify` | list of string | `[ ]` | List of additional address to send DNS NOTIFY messages to. |
| `my.pdns.auth.bind.zones` | attribute set of (submodule) | `{ }` | BIND-style zones definitions. |
| `my.pdns.auth.bind.zones.<name>.also-notify` | list of string | `[ ]` | List of additional address to send DNS NOTIFY messages to. |
| `my.pdns.auth.bind.zones.<name>.masters` | list of string | `[ ]` | List of masters to retrieve data from (as slave). |
| `my.pdns.auth.bind.zones.<name>.path` | absolute path | `null` | Path to zone file. |
| `my.pdns.auth.bind.zones.<name>.template` | boolean | `true` | Whether to run the zone contents through a template for post-processing. |
| `my.pdns.auth.bind.zones.<name>.text` | null or strings concatenated with "\n" | `null` | Inline content of the zone file. |
| `my.pdns.auth.bind.zones.<name>.type` | one of "master", "slave", "native" | `"native"` | Zone type. |
| `my.pdns.auth.enable` | boolean | `false` | Whether to enable PowerDNS authoritative nameserver. |
| `my.pdns.auth.extraSettingsFile` | null or string | `null` | Path to extra settings (e.g. for secrets). |
| `my.pdns.auth.settings` | attribute set of (null or signed integer or string or boolean or absolute path or list of (signed integer or string or boolean or absolute path)) | `{ }` | Authoritative server settings. |
| `my.pdns.recursor.enable` | boolean | `false` | Whether to enable PowerDNS recursive nameserver. |
| `my.pdns.recursor.extraSettingsFile` | null or string | `null` | Path to extra settings (e.g. for secrets). |

## `secrets` — [`nixos/modules/secrets.nix`](../../nixos/modules/secrets.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.secrets.files` | attribute set of unspecified value | `{ }` | Secrets to decrypt with agenix. |
| `my.secrets.key` | null or string | `null` | Public key that secrets for this system should be encrypted for. |
| `my.secrets.vmKeyPath` | string | `"/tmp/xchg/dev.key"` | Path to dev key when in a dev VM. |

## `server` — [`nixos/modules/server.nix`](../../nixos/modules/server.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.server.enable` | boolean | `false` | Whether to enable common configuration for servers. |

## `spdk` — [`nixos/modules/spdk.nix`](../../nixos/modules/spdk.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.spdk.config.subsystems` | attribute set of list of (submodule) | `{ }` | Subsystem config / RPCs. |
| `my.spdk.config.subsystems.<name>.*.method` | string | `null` | RPC method name. |
| `my.spdk.config.subsystems.<name>.*.params` | attribute set of unspecified value | `{ }` | RPC params |
| `my.spdk.debugCommands` | strings concatenated with "\n" | `""` | Commands to run with the spdk-debug script. |
| `my.spdk.enable` | boolean | `false` | Whether to enable SPDK target. |
| `my.spdk.extraArgs` | string | `""` | Extra arguments to pass to spdk_tgt. |

## `tmproot` — [`nixos/modules/tmproot.nix`](../../nixos/modules/tmproot.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.tmproot.enable` | boolean | `true` | Whether to enable tmproot. |
| `my.tmproot.persistence.config` | submodule | `{ }` | Persistence configuration |
| `my.tmproot.persistence.dir` | null or string | `"/persist"` | Path where persisted files are stored. |
| `my.tmproot.size` | string | `"2G"` | Size of tmpfs root |
| `my.tmproot.unsaved.ignore` | list of string | `[ ]` | Path prefixes to ignore if unsaved. |
| `my.tmproot.unsaved.showMotd` | boolean | `true` | Whether to show unsaved files with `dynamic-motd`. |

## `user` — [`nixos/modules/user.nix`](../../nixos/modules/user.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.user.config` | submodule | `{ }` | User definition (as `users.users.*`). |
| `my.user.enable` | boolean | `true` | Whether to create a primary user. |
| `my.user.homeConfig` | Home Manager module | `{ }` | Home configuration (as `home-manager.users.*`) |
| `my.user.passwordSecret` | null or string | `"user-passwd.txt"` | Name of user password secret. |
| `my.user.tmphome` | boolean | `true` | Whether to persist home directory files under tmproot |

## `vms` — [`nixos/modules/vms.nix`](../../nixos/modules/vms.nix)

| Option | Type | Default | Description |
|---|---|---|---|
| `my.vms.instances` | attribute set of (submodule) | `{ }` | VM instances. |
| `my.vms.instances.<name>.autoStart` | boolean | `true` | Whether to start the VM automatically at boot. |
| `my.vms.instances.<name>.boot` | string or (attribute set of unspecified value) convertible to it | `{ menu = "on"; splash-time = 5000; }` | Boot options. |
| `my.vms.instances.<name>.cleanShutdown.enabled` | boolean | `true` | Whether to attempt to cleanly shut down the guest. |
| `my.vms.instances.<name>.cleanShutdown.timeout` | unsigned integer, meaning >=0 | `30` | Clean shutdown timeout (in seconds). |
| `my.vms.instances.<name>.cpu` | string | `"host"` | QEMU CPU model. |
| `my.vms.instances.<name>.drives` | list of (submodule) | `[ ]` | Drives to attach to VM. |
| `my.vms.instances.<name>.drives.*.backend` | string or (attribute set of unspecified value) convertible to it | `{ }` | Backend blockdev options. |
| `my.vms.instances.<name>.drives.*.format` | string or (attribute set of unspecified value) convertible to it | `{ }` | Format blockdev options. |
| `my.vms.instances.<name>.drives.*.formatBackendProp` | string | `"file"` | Property that references the backend blockdev. |
| `my.vms.instances.<name>.drives.*.frontend` | string | `"virtio-blk"` | Frontend device driver. |
| `my.vms.instances.<name>.drives.*.frontendOpts` | string or (attribute set of unspecified value) convertible to it | `{ }` | Frontend device options. |
| `my.vms.instances.<name>.drives.*.name` | string | `null` | Drive name. |
| `my.vms.instances.<name>.enableKVM` | boolean | `true` | Whether to enable KVM. |
| `my.vms.instances.<name>.enableUEFI` | boolean | `true` | Whether to enable UEFI. |
| `my.vms.instances.<name>.hostDevices` | attribute set of (submodule) | `{ }` | Host PCI devices to pass to the VM. |
| `my.vms.instances.<name>.hostDevices.<name>.bindVFIO` | boolean | `true` | Whether to automatically bind the device to vfio-pci. |
| `my.vms.instances.<name>.hostDevices.<name>.extraOptions` | string or (attribute set of unspecified value) convertible to it | `{ }` | Extra QEMU options for the vfio-pci QEMU device. |
| `my.vms.instances.<name>.hostDevices.<name>.hostBDF` | string | `null` | PCI BDF of host device. |
| `my.vms.instances.<name>.hostDevices.<name>.index` | unsigned integer, meaning >=0 | `null` | Index of device in guest (for root port chassis and slot). |
| `my.vms.instances.<name>.machine` | string | `"q35"` | QEMU machine type. |
| `my.vms.instances.<name>.memory` | unsigned integer, meaning >=0 | `1024` | Amount of RAM (mebibytes). |
| `my.vms.instances.<name>.networks` | attribute set of (submodule) | `{ }` | Networks to attach VM to. |
| `my.vms.instances.<name>.networks.<name>.bridge` | null or string | `"‹name›"` | Network bridge to connect to (null to not attach to bridge). |
| `my.vms.instances.<name>.networks.<name>.extraOptions` | string or (attribute set of unspecified value) convertible to it | `{ }` | Extra QEMU options to set for the NIC. |
| `my.vms.instances.<name>.networks.<name>.ifname` | string | `"vm-‹name›"` | TAP device to create / use. |
| `my.vms.instances.<name>.networks.<name>.mac` | string | `null` | Guest MAC address. |
| `my.vms.instances.<name>.networks.<name>.model` | string | `"virtio-net"` | Device type for network interface. |
| `my.vms.instances.<name>.networks.<name>.tapFD` | null or (unsigned integer, meaning >=0) | `null` | FD to use to pass existing TAP device. |
| `my.vms.instances.<name>.networks.<name>.waitOnline` | boolean or string | `true` | Whether to wait for networkd to consider the bridge / existing TAP device online. Pass a string to set the OPERSTATE will wait for. |
| `my.vms.instances.<name>.qemuBin` | absolute path | `"/nix/store/2lkr0v29a67jybn8ckjawpg08y0yizfp-qemu-host-cpu-only-11.1.0/bin/qemu-kvm"` | Path to QEMU executable. |
| `my.vms.instances.<name>.qemuFlags` | list of string | `[ ]` | Additional flags to pass to QEMU. |
| `my.vms.instances.<name>.smp.cpus` | unsigned integer, meaning >=0 | `1` | Number of CPU cores. |
| `my.vms.instances.<name>.smp.threads` | unsigned integer, meaning >=0 | `1` | Number of threads per core. |
| `my.vms.instances.<name>.spice.enable` | boolean | `true` | Whether to enable SPICE. |
| `my.vms.instances.<name>.uuid` | string | `null` | QEMU machine UUID. |
| `my.vms.instances.<name>.vga` | string | `"virtio"` | VGA card type. |
| `my.vms.ovmfPackage` | package | `<derivation OVMF-202605>` | OVMF package. |
