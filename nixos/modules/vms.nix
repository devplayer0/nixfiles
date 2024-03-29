{ lib, pkgs, config, ... }:
let
  inherit (builtins) filter any attrNames attrValues fetchGit;
  inherit (lib)
    unique optional optionals optionalString flatten concatStringsSep
    concatMapStringsSep mapAttrsToList mapAttrs' filterAttrs mkIf mkMerge
    mkDefault mkOption;
  inherit (lib.my) mkOpt' mkBoolOpt';

  flattenQEMUOpts = attrs:
    concatStringsSep
      ","
      (mapAttrsToList
        (k: v: if (v != null) then "${k}=${toString v}" else k)
        attrs);
  qemuOpts = with lib.types; coercedTo (attrsOf unspecified) flattenQEMUOpts str;
  extraQEMUOpts = o: optionalString (o != "") ",${o}";

  doCleanShutdown =
  let
    pyEnv = pkgs.python3.withPackages (ps: with ps; [ qemu ]);
  in
    pkgs.writeScript "qemu-clean-shutdown" ''
      #!${pyEnv}/bin/python
      import asyncio
      import sys
      import os

      import qemu.qmp

      async def main():
        if len(sys.argv) != 2:
          print(f'usage: {sys.argv[0]} <qmp unix socket>', file=sys.stderr)
          sys.exit(1)

        if 'MAINPID' not in os.environ:
            # Special case: systemd is calling us after QEMU exited on its own
            sys.exit(0)

        client = qemu.qmp.QMPClient('clean-shutdown')
        await client.connect(sys.argv[1])
        await client.execute('system_powerdown')
        async for event in client.events:
          if event['event'] == 'SHUTDOWN':
            break
        await client.disconnect()

      asyncio.run(main())
    '';

  cfg = config.my.vms;

  netOpts = with lib.types; { name, iName, ... }: {
    options = {
      ifname = mkOpt' str "vm-${iName}" "TAP device to create / use.";
      bridge = mkOpt' (nullOr str) name "Network bridge to connect to (null to not attach to bridge).";
      waitOnline = mkOpt' (either bool str) true
        "Whether to wait for networkd to consider the bridge / existing TAP device online. Pass a string to set the OPERSTATE will wait for.";
      tapFD = mkOpt' (nullOr ints.unsigned) null "FD to use to pass existing TAP device.";

      model = mkOpt' str "virtio-net" "Device type for network interface.";
      mac = mkOpt' str null "Guest MAC address.";
      extraOptions = mkOpt' qemuOpts { } "Extra QEMU options to set for the NIC.";
    };
  };

  driveOpts = with lib.types; {
    options = {
      name = mkOpt' str null "Drive name.";
      backend = mkOpt' qemuOpts { } "Backend blockdev options.";

      format = mkOpt' qemuOpts { } "Format blockdev options.";
      formatBackendProp = mkOpt' str "file" "Property that references the backend blockdev.";

      frontend = mkOpt' str "virtio-blk" "Frontend device driver.";
      frontendOpts = mkOpt' qemuOpts { } "Frontend device options.";
    };
  };

  hostDevOpts = with lib.types; {
    options = {
      index = mkOpt' ints.unsigned null "Index of device in guest (for root port chassis and slot).";
      hostBDF = mkOpt' str null "PCI BDF of host device.";
      bindVFIO = mkBoolOpt' true "Whether to automatically bind the device to vfio-pci.";
      extraOptions = mkOpt' qemuOpts { } "Extra QEMU options for the vfio-pci QEMU device.";
    };
  };

  vmOpts = with lib.types; { name, ... }: {
    options = {
      qemuBin = mkOpt' path "${pkgs.qemu_kvm}/bin/qemu-kvm" "Path to QEMU executable.";
      qemuFlags = mkOpt' (listOf str) [ ] "Additional flags to pass to QEMU.";
      autoStart = mkBoolOpt' true "Whether to start the VM automatically at boot.";
      cleanShutdown = {
        enabled = mkBoolOpt' true "Whether to attempt to cleanly shut down the guest.";
        timeout = mkOpt' ints.unsigned 30 "Clean shutdown timeout (in seconds).";
      };

      uuid = mkOpt' str null "QEMU machine UUID.";
      machine = mkOpt' str "q35" "QEMU machine type.";
      enableKVM = mkBoolOpt' true "Whether to enable KVM.";
      enableUEFI = mkBoolOpt' true "Whether to enable UEFI.";
      cpu = mkOpt' str "host" "QEMU CPU model.";
      smp = {
        cpus = mkOpt' ints.unsigned 1 "Number of CPU cores.";
        threads = mkOpt' ints.unsigned 1 "Number of threads per core.";
      };
      memory = mkOpt' ints.unsigned 1024 "Amount of RAM (mebibytes).";
      boot = mkOpt' qemuOpts { menu = "on"; splash-time = 5000; } "Boot options.";
      vga = mkOpt' str "virtio" "VGA card type.";
      spice.enable = mkBoolOpt' true "Whether to enable SPICE.";
      networks = mkOption {
        description = "Networks to attach VM to.";
        type = attrsOf (submoduleWith {
          modules = [ { _module.args.iName = name; } netOpts ];
        });
        default = { };
      };
      drives = mkOpt' (listOf (submodule driveOpts)) [ ] "Drives to attach to VM.";
      hostDevices = mkOpt' (attrsOf (submodule hostDevOpts)) { } "Host PCI devices to pass to the VM.";
    };
  };

  allHostDevs =
    flatten
      (map
        (i: mapAttrsToList (name: c: c // { inherit name; }) i.hostDevices)
        (attrValues cfg.instances));
  anyVfioDevs = any (d: d.bindVFIO);
  vfioHostDevs = filter (d: d.bindVFIO);

  mkQemuScript = n: i:
  let
    flags =
      i.qemuFlags ++
      [
        "name ${n}"
        "uuid ${i.uuid}"
        "machine ${i.machine}"
        "cpu ${i.cpu}"
        "smp cores=${toString i.smp.cpus},threads=${toString i.smp.threads}"
        "m ${toString i.memory}"
        "boot ${toString i.boot}"
        "nographic"
        "vga ${i.vga}"
        "chardev socket,id=monitor-qmp,path=/run/vms/${n}/monitor-qmp.sock,server=on,wait=off"
        "mon chardev=monitor-qmp,mode=control"
        "chardev socket,id=monitor,path=/run/vms/${n}/monitor.sock,server=on,wait=off"
        "mon chardev=monitor,mode=readline"
        "chardev socket,id=tty,path=/run/vms/${n}/tty.sock,server=on,wait=off"
        "device isa-serial,chardev=tty"
      ] ++
      (optional i.enableKVM "enable-kvm") ++
      (optionals i.enableUEFI [
        "drive if=pflash,format=raw,unit=0,readonly=on,file=${cfg.ovmfPackage.fd}/FV/OVMF_CODE.fd"
        "drive if=pflash,format=raw,unit=1,file=/var/lib/vms/${n}/ovmf_vars.bin"
      ]) ++
      (optional i.spice.enable "spice unix=on,addr=/run/vms/${n}/spice.sock,disable-ticketing=on") ++
      (flatten (mapAttrsToList (nn: c: [
        ("netdev tap,id=${nn}," + (
          if (c.tapFD != null)
            then "fd=${toString c.tapFD} ${toString c.tapFD}<>/dev/tap$(cat /sys/class/net/${c.ifname}/ifindex)"
            else "ifname=${c.ifname},script=no,downscript=no"))
        ("device ${c.model},netdev=${nn},mac=${c.mac}" + (extraQEMUOpts c.extraOptions))
      ]) i.networks)) ++
      (optional (i.networks == { }) "nic none") ++
      (flatten (map (d: [
        "blockdev node-name=${d.name}-backend,${d.backend}"
        "blockdev node-name=${d.name}-format,${d.formatBackendProp}=${d.name}-backend,${d.format}"
        ("device ${d.frontend},id=${d.name},drive=${d.name}-format" + (extraQEMUOpts d.frontendOpts))
      ]) i.drives)) ++
      (flatten (mapAttrsToList (id: c: [
        "device pcie-root-port,id=${id}-port,chassis=${toString c.index},port=${toString c.index}"
        ("device vfio-pci,bus=${id}-port,host=${c.hostBDF}" + (extraQEMUOpts c.extraOptions))
      ]) i.hostDevices));
    args = map (v: "-${v}") flags;
  in
  ''
    exec ${i.qemuBin} \
      ${concatStringsSep " \\\n  " args}
  '';
in
{
  options.my.vms = with lib.types; {
    instances = mkOpt' (attrsOf (submodule vmOpts)) { } "VM instances.";
    ovmfPackage = mkOpt' package pkgs.OVMF "OVMF package.";
  };

  config = mkIf (cfg.instances != { }) {
    assertions = [
      {
        assertion = let bdfs = map (d: d.hostBDF) allHostDevs; in (unique bdfs) == bdfs;
        message = "VMs cannot share host devices!";
      }
    ];

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "vm-tty" ''
        [ $# -eq 1 ] || (echo "usage: $0 <vm>" >&2; exit 1)
        exec ${pkgs.minicom}/bin/minicom -D unix#/run/vms/"$1"/tty.sock
      '')
    ];

    services.udev = {
      packages =
        optionals
          (anyVfioDevs allHostDevs)
          [
            pkgs.vfio-pci-bind
            (pkgs.writeTextDir
              "etc/udev/rules.d/20-vfio-tags.rules"
              (concatMapStringsSep
                "\n"
                (d: ''ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:${d.hostBDF}", TAG="vfio-pci-bind"'')
                (vfioHostDevs allHostDevs)))
          ];
    };

    my.tmproot.persistence.config.directories = [ "/var/lib/vms" ];

    systemd = mkMerge ([ ] ++
      (mapAttrsToList (n: i: {
        # TODO: LLDP?
        network.networks =
          mapAttrs'
            (nn: net: {
              name = "70-vm-${n}-${nn}";
              value = {
                matchConfig = {
                  Name = net.ifname;
                  Kind = "tun";
                };
                networkConfig.Bridge = net.bridge;
              };
            })
            (filterAttrs (_: net: net.bridge != null) i.networks);
        services."vm@${n}" =
        let
          dependencies =
            map
              (net:
              let
                ifname = if net.bridge != null then net.bridge else net.ifname;
                arg = if net.waitOnline == true then ifname else "${ifname}:${net.waitOnline}";
              in
              "systemd-networkd-wait-online@${arg}.service")
              (filter (net: (net.bridge != null || net.tapFD != null) && net.waitOnline != false) (attrValues i.networks));
        in
        {
          description = "Virtual machine '${n}'";
          # Use `Wants=` instead of `Requires=`. Otherwise restarting the wait-online services will cause the VM to
          # restart as well.
          wants = dependencies;
          after = dependencies;
          serviceConfig = {
            ExecStop = mkIf i.cleanShutdown.enabled "${doCleanShutdown} /run/vms/${n}/monitor-qmp.sock";
            TimeoutStopSec = mkIf i.cleanShutdown.enabled i.cleanShutdown.timeout;

            RuntimeDirectory = "vms/${n}";
            StateDirectory = "vms/${n}";
          };

          preStart =
          let
            hostDevs = attrValues i.hostDevices;
          in
            ''
              if [ ! -e "$STATE_DIRECTORY"/ovmf_vars.bin ]; then
                cp "${cfg.ovmfPackage.fd}"/FV/OVMF_VARS.fd "$STATE_DIRECTORY"/ovmf_vars.bin
              fi

              ${optionalString (anyVfioDevs hostDevs) ''
                iommu_group() {
                  g=/sys/bus/pci/devices/0000:$1/iommu_group
                  until [ -e $g ]; do
                    sleep 0.1
                  done
                  basename $(readlink $g)
                }
                wait_vfio() {
                  until [ -e /dev/vfio/$(iommu_group $1) ]; do
                    sleep 0.1
                  done
                }

                ${concatMapStringsSep "\n" (d: "wait_vfio ${d.hostBDF}") (vfioHostDevs hostDevs) }
              ''}
            '';
          script = mkQemuScript n i;
          postStart =
            ''
              socks=(monitor-qmp monitor tty spice)
              for s in ''${socks[@]}; do
                path="$RUNTIME_DIRECTORY"/''${s}.sock
                until [ -e "$path" ]; do sleep 0.1; done
                chgrp kvm "$path"
                chmod 770 "$path"
              done
            '';
          restartIfChanged = mkDefault false;
          wantedBy = optional i.autoStart "machines.target";
        };
      }) cfg.instances));
  };
}
