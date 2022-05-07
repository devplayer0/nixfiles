{ lib, pkgs, config, ... }:
let
  inherit (lib) optional optionals optionalString flatten concatStringsSep mapAttrsToList mapAttrs' mkIf mkDefault;
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
    pyEnv = pkgs.python310.withPackages (ps: with ps; [ qemu ]);
  in
    pkgs.writeScript "qemu-clean-shutdown" ''
      #!${pyEnv}/bin/python
      import sys
      import os

      import qemu.qmp

      if len(sys.argv) != 2:
        print(f'usage: {sys.argv[0]} <qmp unix socket>', file=sys.stderr)
        sys.exit(1)

      if not os.path.exists(sys.argv[1]) and 'MAINPID' not in os.environ:
          # Special case: systemd is calling us after QEMU exited on its own
          sys.exit(0)

      with qemu.qmp.QEMUMonitorProtocol(sys.argv[1]) as mon:
        mon.connect()
        mon.command('system_powerdown')
        while mon.pull_event(wait=True)['event'] != 'SHUTDOWN':
          pass
    '';

  cfg = config.my.vms;

  netOpts = with lib.types; { name, ... }: {
    options = {
      bridge = mkOpt' str name "Network bridge to connect to.";
      model = mkOpt' str "virtio-net" "Device type for network interface.";
      extraOptions = mkOpt' qemuOpts { } "Extra QEMU options to set for the NIC.";
    };
  };

  driveOpts = with lib.types; {
    options = {
      backend = mkOpt' qemuOpts { } "Backend blockdev options.";

      format = mkOpt' qemuOpts { } "Format blockdev options.";
      formatBackendProp = mkOpt' str "file" "Property that references the backend blockdev.";

      frontend = mkOpt' str "virtio-blk" "Frontend device driver.";
      frontendOpts = mkOpt' qemuOpts { } "Frontend device options.";
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

      machine = mkOpt' str "q35" "QEMU machine type.";
      enableKVM = mkBoolOpt' true "Whether to enable KVM.";
      enableUEFI = mkBoolOpt' true "Whether to enable UEFI.";
      cpu = mkOpt' str "host" "QEMU CPU model.";
      smp = {
        cpus = mkOpt' ints.unsigned 1 "Number of CPU cores.";
        threads = mkOpt' ints.unsigned 1 "Number of threads per core.";
      };
      memory = mkOpt' ints.unsigned 1024 "Amount of RAM (mebibytes).";
      vga = mkOpt' str "qxl" "VGA card type.";
      spice.enable = mkBoolOpt' true "Whether to enable SPICE.";
      networks = mkOpt' (attrsOf (submodule netOpts)) { } "Networks to attach VM to.";
      drives = mkOpt' (attrsOf (submodule driveOpts)) { } "Drives to attach to VM.";
    };
  };

  mkQemuCommand = n: i:
  let
    flags =
      i.qemuFlags ++
      [
        "name ${n}"
        "machine ${i.machine}"
        "cpu ${i.cpu}"
        "smp cpus=${toString i.smp.cpus},threads=${toString i.smp.threads}"
        "m ${toString i.memory}"
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
        "netdev bridge,id=${nn},br=${c.bridge}"
        ("device ${c.model},netdev=${nn}" + (extraQEMUOpts c.extraOptions))
      ]) i.networks)) ++
      (flatten (mapAttrsToList (dn: c: [
        "blockdev node-name=${dn}-backend,${c.backend}"
        "blockdev node-name=${dn}-format,${c.formatBackendProp}=${dn}-backend,${c.format}"
        ("device ${c.frontend},id=${dn},drive=${dn}-format" + (extraQEMUOpts c.frontendOpts))
      ]) i.drives));
    args = map (v: "-${v}") flags;
  in
    concatStringsSep " " ([ i.qemuBin ] ++ args);
in
{
  options.my.vms = with lib.types; {
    instances = mkOpt' (attrsOf (submodule vmOpts)) { } "VM instances.";
    ovmfPackage = mkOpt' package pkgs.OVMF "OVMF package.";
  };

  config = mkIf (cfg.instances != { }) {
    # qemu-bridge-helper will fail otherwise
    environment.etc."qemu/bridge.conf".text = "allow all";
    systemd = {
      services = mapAttrs' (n: i: {
        name = "vm@${n}";
        value = {
          description = "Virtual machine '${n}'";
          serviceConfig = {
            ExecStart = mkQemuCommand n i;
            ExecStop = mkIf i.cleanShutdown.enabled "${doCleanShutdown} /run/vms/${n}/monitor-qmp.sock";
            TimeoutStopSec = mkIf i.cleanShutdown.enabled i.cleanShutdown.timeout;

            RuntimeDirectory = "vms/${n}";
            StateDirectory = "vms/${n}";
          };

          preStart =
            ''
              if [ ! -e "$STATE_DIRECTORY"/ovmf_vars.bin ]; then
                cp "${cfg.ovmfPackage.fd}"/FV/OVMF_VARS.fd "$STATE_DIRECTORY"/ovmf_vars.bin
              fi
            '';
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
      }) cfg.instances;
    };
  };
}
