{ lib, extendModules, modulesPath, baseModules, options, config, ... }:
let
  inherit (lib) recursiveUpdate mkOption;
  inherit (lib.my) mkBoolOpt;

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
  options.my = with lib.types; {
    boot.isDevVM = mkBoolOpt false;
    build = options.system.build;
    asDevVM = mkOption {
      inherit (asDevVM) type;
      default = { };
      visible = "shallow";
    };
  };

  config.my.build = {
    # The meta.mainProgram should probably be set upstream but oh well...
    devVM = recursiveUpdate config.my.asDevVM.system.build.vm { meta.mainProgram = "run-${config.system.name}-vm"; };
  };
}
