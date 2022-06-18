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

      if 'MAINPID' not in os.environ:
          # Special case: systemd is calling us after QEMU exited on its own
          sys.exit(0)

      with qemu.qmp.QEMUMonitorProtocol(sys.argv[1]) as mon:
        mon.connect()
        mon.command('system_powerdown')
        while mon.pull_event(wait=True)['event'] != 'SHUTDOWN':
          pass
    '';

  # TODO: Upstream or something...
  vfio-pci-bind = pkgs.stdenv.mkDerivation rec {
    pname = "vfio-pci-bind";
    version = "b41e4545b21de434fc51a34a9bf1d72e3ac66cc8";

    src = fetchGit {
      url = "https://github.com/andre-richter/vfio-pci-bind";
      rev = version;
    };

    prePatch = ''
      substituteInPlace vfio-pci-bind.sh \
        --replace modprobe ${pkgs.kmod}/bin/modprobe
      substituteInPlace 25-vfio-pci-bind.rules \
        --replace vfio-pci-bind.sh "$out"/bin/vfio-pci-bind.sh
    '';
    installPhase = ''
      mkdir -p "$out"/bin/ "$out"/lib/udev/rules.d
      cp vfio-pci-bind.sh "$out"/bin/
      cp 25-vfio-pci-bind.rules "$out"/lib/udev/rules.d/
    '';
  };

  cfg = config.my.vms;

  netOpts = with lib.types; { name, iName, ... }: {
    options = {
      ifname = mkOpt' str "vm-${iName}" "TAP device to create ";
      bridge = mkOpt' (nullOr str) name "Network bridge to connect to (null to not attach to bridge).";
      waitOnline = mkOpt' (either bool str) true
        "Whether to wait for networkd to consider the bridge online. Pass a string to set the OPERSTATE will wait for.";

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
      bindVFIO = mkBoolOpt' true "Whether to automatically bind the device to vfio-pci.";
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
      drives = mkOpt' (listOf (submodule driveOpts)) { } "Drives to attach to VM.";
      hostDevices = mkOpt' (attrsOf (submodule hostDevOpts)) { } "Host PCI devices to pass to the VM.";
    };
  };

  allHostDevs =
    flatten
      (map
        (i: mapAttrsToList (bdf: c: { inherit bdf; inherit (c) bindVFIO; }) i.hostDevices)
        (attrValues cfg.instances));

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
        "netdev tap,id=${nn},ifname=${c.ifname},script=no"
        ("device ${c.model},netdev=${nn},mac=${c.mac}" + (extraQEMUOpts c.extraOptions))
      ]) i.networks)) ++
      (flatten (map (d: [
        "blockdev node-name=${d.name}-backend,${d.backend}"
        "blockdev node-name=${d.name}-format,${d.formatBackendProp}=${d.name}-backend,${d.format}"
        ("device ${d.frontend},id=${d.name},drive=${d.name}-format" + (extraQEMUOpts d.frontendOpts))
      ]) i.drives)) ++
      (map (bdf: "device vfio-pci,host=${bdf}") (attrNames i.hostDevices));
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
        assertion = let bdfs = map (d: d.bdf) allHostDevs; in (unique bdfs) == bdfs;
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
          (any (d: d.bindVFIO) allHostDevs)
          [
            vfio-pci-bind
            (pkgs.writeTextDir
              "etc/udev/rules.d/20-vfio-tags.rules"
              (concatMapStringsSep
                "\n"
                (d: ''ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:${d.bdf}", TAG="vfio-pci-bind"'')
                (filter (d: d.bindVFIO) allHostDevs)))
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
                  Kind = "tap";
                };
                networkConfig.Bridge = net.bridge;
              };
            })
            (filterAttrs (_: net: net.bridge != null) i.networks);
        services."vm@${n}" = {
          description = "Virtual machine '${n}'";
          requires =
            map
              (net:
              let
                arg = if net.waitOnline == true then net.bridge else "${net.bridge}:${net.waitOnline}";
              in
              "systemd-networkd-wait-online@${arg}.service")
              (filter (net: net.bridge != null && net.waitOnline != false) (attrValues i.networks));
          serviceConfig = {
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
