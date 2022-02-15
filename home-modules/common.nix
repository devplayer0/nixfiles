{ lib, pkgs, pkgs', inputs, config, ... }@args:
let
  inherit (lib) optionalAttrs versionAtLeast mkMerge mkIf mkDefault mkOption;
  inherit (lib.my) mkOpt' dummyOption;
in
{
  options = with lib.types; {
    my = {
      isStandalone = mkOption {
        type = bool;
        internal = true;
        description = "Whether home-manager is running inside a NixOS system or not.";
      };
    };

    # Only present in >=22.05, so forward declare
    nix.registry = dummyOption;
  };
  config = mkMerge [
    (mkIf (versionAtLeast config.home.stateVersion "22.05") {
      nix.registry = {
        pkgs = {
          to = {
            type = "path";
            path = toString pkgs.path;
          };
          exact = true;
        };
      };
    })
    {
      my.isStandalone = !(args ? sysConfig);

      programs = {
        # Even when enabled this will only be actually installed in standalone mode
        # Note: `home-manager.path` is for telling home-manager is installed and setting it in NIX_PATH, which we should
        # never care about.
        home-manager.enable = true;

        bash = {
          # This not only installs bash but has home-manager control .bashrc and friends
          enable = mkDefault true;
        };

        direnv = {
          enable = mkDefault true;
          nix-direnv.enable = true;
          stdlib =
            ''
              # addition to nix-direnv's use_nix that registers outputs as gc roots (as well as the .drv)
              use_nix_outputs() {
                local layout_dir drv deps
                layout_dir="$(direnv_layout_dir)"
                drv="$layout_dir/drv"
                deps="$layout_dir/deps"

                if [ ! -e "$deps" ] || (( "$(stat --format=%Z "$drv")" > "$(stat --format=%Z "$deps")" )); then
                  rm -rf "$deps"
                  mkdir -p "$deps"
                  nix-store --indirect --add-root "$deps/out" --realise $(nix-store --query --references "$drv") > /dev/null
                  log_status renewed outputs gc roots
                fi
              }
            '';
        };

        htop = {
          enable = true;
          settings = {};
        };
      };

      home = {
        packages = with pkgs; [
          tree
          iperf3
        ];

        sessionVariables = {
          EDITOR = "vim";
        };

        language.base = mkDefault "en_IE.UTF-8";
      };
    }
    (mkIf (config.my.isStandalone || !args.sysConfig.home-manager.useGlobalPkgs) {
      # Note: If globalPkgs mode is on, then these will be overridden by the NixOS equivalents of these options
      nixpkgs = {
        overlays = [
          (final: prev: { nix = inputs.nix.defaultPackage.${config.nixpkgs.system}; })
          # TODO: Wait for https://github.com/NixOS/nixpkgs/pull/159074 to arrive to nixos-unstable
          (final: prev: { remarshal = pkgs'.master.remarshal; })
        ];
        config = {
          allowUnfree = true;
        };
      };
    })
    (mkIf config.my.isStandalone {
      fonts.fontconfig.enable = true;

      home = {
        packages = with pkgs; [
          nix
        ];
      };
    })
  ];
}
