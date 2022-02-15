{ lib, extendModules, modulesPath, baseModules, options, config, ... }:
let
  inherit (lib) recursiveUpdate mkOption mkDefault;
  inherit (lib.my) mkBoolOpt' dummyOption;

  cfg = config.my.build;

  asDevVM = extendModules {
    # TODO: Hack because this is kinda broken on 21.11 (https://github.com/NixOS/nixpkgs/issues/148343)
    specialArgs = { inherit baseModules; };
    modules = [
      "${modulesPath}/virtualisation/qemu-vm.nix"
      ({ ... }: {
        my.boot.isDevVM = true;
      })
    ];
  };
in
{
  options = with lib.types; {
    my = {
      boot.isDevVM = mkBoolOpt' false "Whether the system is a development VM.";
      build = options.system.build;
      asDevVM = mkOption {
        inherit (asDevVM) type;
        default = { };
        visible = "shallow";
        description = "Configuration as a development VM";
      };
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
    my.build = {
      # The meta.mainProgram should probably be set upstream but oh well...
      devVM = recursiveUpdate config.my.asDevVM.system.build.vm { meta.mainProgram = "run-${config.system.name}-vm"; };
    };
  };

  meta.buildDocsInSandbox = false;
}
