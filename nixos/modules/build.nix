{ lib, pkgs, extendModules, modulesPath, options, config, ... }:
let
  inherit (lib) recursiveUpdate mkOption mkDefault mkIf mkMerge flatten optional;
  inherit (lib.my) mkBoolOpt' dummyOption;

  cfg = config.my.build;

  allHardware = (optional config.my.build.allHardware { imports = [ "${modulesPath}/profiles/all-hardware.nix" ]; });

  asDevVM = extendModules {
    modules = [
      "${modulesPath}/virtualisation/qemu-vm.nix"
      { my.build.isDevVM = true; }
    ];
  };
  asISO = extendModules {
    modules = flatten [
      "${modulesPath}/installer/cd-dvd/iso-image.nix"
      allHardware
      {
        # Doesn't work right now... (missing /dev/root)
        boot.initrd.systemd.enable = false;

        isoImage = {
          makeEfiBootable = true;
          makeUsbBootable = true;
          # Not necessarily an installer
          appendToMenuLabel = mkDefault "";

          squashfsCompression = "zstd -Xcompression-level 8";
        };
      }
    ];
  };
  asContainer = extendModules {
    modules = [
      {
        boot.isContainer = true;
      }
    ];
  };
  asKexecTree = extendModules {
    modules = flatten [
      "${modulesPath}/installer/netboot/netboot.nix"
      allHardware
      ({ pkgs, config, ... }: {
        system.build.netbootArchive = pkgs.runCommand "netboot-${config.system.name}-archive.tar" { } ''
          ${pkgs.gnutar}/bin/tar -rvC "${config.system.build.kernel}" \
            -f "$out" "${config.system.boot.loader.kernelFile}"
          ${pkgs.gnutar}/bin/tar -rvC "${config.system.build.netbootRamdisk}" \
            -f "$out" initrd
          ${pkgs.gnutar}/bin/tar -rvC "${config.system.build.netbootIpxeScript}" \
            -f "$out" netboot.ipxe
        '';
      })
    ];
  };

  mkAsOpt = ext: desc: with lib.types; mkOption {
    type = unspecified;
    default = ext;
    visible = "shallow";
    description = "Configuration as ${desc}.";
  };
in
{
  options = {
    my = {
      build = {
        isDevVM = mkBoolOpt' false "Whether the system is a development VM.";
        allHardware = mkBoolOpt' false
          ("Whether to enable a lot of firmware and kernel modules for a wide range of hardware." +
          "Only applies to some build targets.");
      };

      asDevVM = mkAsOpt asDevVM "a development VM";
      asISO = mkAsOpt asISO "a bootable .iso image";
      asContainer = mkAsOpt asContainer "a container";
      asKexecTree = mkAsOpt asKexecTree "a kexec-able kernel and initrd";

      buildAs = options.system.build;
    };

    # Forward declare options that won't exist until the VM module is actually imported
    virtualisation = {
      diskImage = dummyOption;
      forwardPorts = dummyOption;
      sharedDirectories = dummyOption;
      cores = dummyOption;
      memorySize = dummyOption;
      qemu.options = dummyOption;
    };
    isoImage = {
      isoBaseName = dummyOption;
      volumeID = dummyOption;
      edition = dummyOption;
      appendToMenuLabel = dummyOption;
    };
  };

  config = {
    virtualisation = {
      diskImage = mkDefault "./.vms/${config.system.name}.qcow2";
    };

    my = {
      buildAs = {
        # The meta.mainProgram should probably be set upstream but oh well...
        devVM = recursiveUpdate config.my.asDevVM.config.system.build.vm { meta.mainProgram = "run-${config.system.name}-vm"; };
        iso = config.my.asISO.config.system.build.isoImage;
        container = config.my.asContainer.config.system.build.toplevel;
        kexecTree = config.my.asKexecTree.config.system.build.kexecTree;
        netbootArchive = config.my.asKexecTree.config.system.build.netbootArchive;
      };
    };
  };

  meta.buildDocsInSandbox = false;
}
