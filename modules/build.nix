{ lib, extendModules, modulesPath, options, config, ... }:
  let
    inherit (lib) mkOption;
    inherit (lib.my) mkBoolOpt;

    cfg = config.my.build;

    # TODO: This is broken on 21.11 (https://github.com/NixOS/nixpkgs/issues/148343)
    asDevVM = extendModules {
      modules = [
        (import "${modulesPath}/virtualisation/qemu-vm.nix")
        ({ config, ... }: {
          my.boot.isDevVM = true;
        })
      ];
    };
  in {
    options.my = with lib.types; {
      boot.isDevVM = mkBoolOpt false;
      build = options.system.build;
      asDevVM = mkOption {
        inherit (asDevVM) type;
        default = {};
        visible = "shallow";
      };
    };

    config.my.build = {
      devVM = config.my.asDevVM.system.build.vm;
    };
  }
