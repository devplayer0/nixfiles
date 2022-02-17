{ lib, extendModules, modulesPath, baseModules, options, config, ... }:
let
  inherit (lib) recursiveUpdate mkOption mkDefault mkIf mkMerge;
  inherit (lib.my) mkBoolOpt' dummyOption;

  cfg = config.my.build;

  asDevVM = extendModules {
    # TODO: Hack because this is kinda broken on 21.11 (https://github.com/NixOS/nixpkgs/issues/148343)
    specialArgs = { inherit baseModules; };
    modules = [
      "${modulesPath}/virtualisation/qemu-vm.nix"
      { my.build.isDevVM = true; }
    ];
  };
  asISO = extendModules {
    # TODO: see previous
    specialArgs = { inherit baseModules; };
    modules = lib.flatten [
      "${modulesPath}/installer/cd-dvd/iso-image.nix"
      (lib.optional config.my.build.allHardware { imports = [ "${modulesPath}/profiles/all-hardware.nix" ]; })
      {
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
in
{
  options = with lib.types; {
    my = {
      build = {
        isDevVM = mkBoolOpt' false "Whether the system is a development VM.";
        allHardware = mkBoolOpt' false
          ("Whether to enable a lot of firmware and kernel modules for a wide range of hardware." +
          "Only applies to some build targets.");
      };

      asDevVM = mkOption {
        inherit (asDevVM) type;
        default = { };
        visible = "shallow";
        description = "Configuration as a development VM";
      };
      asISO = mkOption {
        inherit (asISO) type;
        default = { };
        visible = "shallow";
        description = "Configuration as a bootable .iso image";
      };

      buildAs = options.system.build;
    };

    # Forward declare options that won't exist until the VM module is actually imported
    virtualisation = {
      diskImage = dummyOption;
    };
  };

  config = {
    virtualisation = {
      diskImage = mkDefault "./.vms/${config.system.name}.qcow2";
    };

    my = {
      buildAs = {
        # The meta.mainProgram should probably be set upstream but oh well...
        devVM = recursiveUpdate config.my.asDevVM.system.build.vm { meta.mainProgram = "run-${config.system.name}-vm"; };
        iso = config.my.asISO.system.build.isoImage;
      };
    };
  };

  meta.buildDocsInSandbox = false;
}
