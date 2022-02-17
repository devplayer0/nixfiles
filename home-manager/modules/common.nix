{ lib, pkgs, pkgs', inputs, options, config, ... }@args:
let
  inherit (builtins) mapAttrs;
  inherit (lib) concatStringsSep optionalAttrs versionAtLeast mkMerge mkIf mkDefault mkOption;
  inherit (lib.hm) dag;
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

      ssh = {
        authKeys = {
          literal = mkOpt' (listOf singleLineStr) [ ] "List of OpenSSH keys to allow";
        };
        matchBlocks = mkOpt' (attrsOf anything) { } "SSH match blocks";
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
      my = {
        isStandalone = !(args ? osConfig);

        ssh = {
          authKeys.literal = [
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC+kCHXqtznkT9IBN5WxZHmXI97k3BumT+N4lyHWMo0pykpACCOcGw52EXxQveNqgcwcRUgamL9A2JTE//WRf3O4nBofeTRNKcRxTjRoUVIt/F0xbf09yWBqJOXZ8rqLkXhRvSpr1TCUZtYVp5iLtpERp622OMIqHSwa6HlxBqsCFkBeq1bRyNtYK/IaQAuBPW9MNeFriGqA0Vq078ccXp+JINxJbr+ZJybVg6PVqnMD+PgGMZQLkoWjwjH3vcJZZt584UPtrXKpNZuKy6dcMCb2U+O9NOaO66168sBVuK0kZHh51nJ7ZH38VLGiBipRgIQ1fzic3Ncn6GC9ko3/OwT jackos1998@gmail.com"
          ];
          matchBlocks = {
            "rsync.net" = {
              host = "rsyncnet";
              user = "16413";
              hostname = "ch-s010.rsync";
            };

            shoe = {
              host = "shoe.netsoc.tcd.ie shoe";
              user = "netsoc";
            };
            netsocBoxes = {
              host = "cube spoon napalm gandalf saruman";
              user = "root";
            };
          };
        };
      };

      home.file.".ssh/authorized_keys".text = mkIf config.programs.ssh.enable
        ''
          ${concatStringsSep "\n" config.my.ssh.authKeys.literal}
        '';

      programs = {
        # Even when enabled this will only be actually installed in standalone mode
        # Note: `home-manager.path` is for telling home-manager is installed and setting it in NIX_PATH, which we should
        # never care about.
        home-manager.enable = true;

        lsd = {
          enable = mkDefault true;
          enableAliases = mkDefault true;
        };

        starship = {
          enable = mkDefault true;
          settings = {
            aws.disabled = true;
          };
        };

        bash = {
          # This not only installs bash but has home-manager control .bashrc and friends
          enable = mkDefault true;
          initExtra =
          ''
            flake-src() {
              cd "$(nix eval "''${@:2}" --impure --raw --expr "builtins.getFlake \"$1\"")"
            }
          '';
        };

        ssh = {
          enable = mkDefault true;
          matchBlocks = (mapAttrs (_: b: dag.entryBefore [ "all" ] b) config.my.ssh.matchBlocks) // {
            all = {
              host = "*";
              identityFile = [
                "~/.ssh/id_rsa"
                "~/.ssh/netsoc"
                "~/.ssh/borg"
              ];
            };
          };
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
        shellAliases = {
          hm = "home-manager";
        };

        language.base = mkDefault "en_IE.UTF-8";
      };
    }
    (mkIf (config.my.isStandalone || !args.osConfig.home-manager.useGlobalPkgs) {
      # Note: If globalPkgs mode is on, then these will be overridden by the NixOS equivalents of these options
      nixpkgs = {
        overlays = [
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
          pkgs'.unstable.nixVersions.stable
        ];
      };
    })
  ];
}
