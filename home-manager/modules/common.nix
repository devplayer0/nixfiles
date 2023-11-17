{ lib, pkgsFlake, pkgs, pkgs', inputs, config, ... }@args:
let
  inherit (builtins) listToAttrs mapAttrs readFile;
  inherit (lib)
    optionalString nameValuePair concatMapStrings concatStringsSep optionalAttrs versionAtLeast
    mapAttrsToList mkMerge mkIf mkDefault mkOption;
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

      shell = mkOpt' str null "User's shell (so NixOS or others can set it externally).";
      fishCompletionsFrequency = mkOpt' (nullOr str) "daily" "How often to generate fish completions from manpages.";

      ssh = {
        authKeys = {
          literal = mkOpt' (listOf singleLineStr) [ ] "List of OpenSSH keys to allow";
          files = mkOpt' (listOf path) [ ] "List of OpenSSH key files to allow";
        };
      };
    };
  };
  config = mkMerge [
    {
      my = {
        isStandalone = !(args ? osConfig);

        shell = mkDefault "${config.programs.fish.package}/bin/fish";
      };

      home = {
        file.".ssh/authorized_keys" = with config.my.ssh.authKeys;
          mkIf (config.programs.ssh.enable && (literal != [ ] || files != [ ])) {
            text = ''
              ${concatStringsSep "\n" literal}
              ${concatMapStrings (f: readFile f + "\n") files}
            '';
          };
      };

      nix = {
        package = mkIf (!(versionAtLeast config.home.stateVersion "22.11")) pkgs.nix;
        settings = {
          experimental-features = [ "nix-command" "flakes" "ca-derivations" ];
          max-jobs = mkDefault "auto";
        };
      };

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
        }
        # We use custom behaviour for this
        // listToAttrs (map (s: nameValuePair "enable${s}Integration" false) [ "Bash" "Zsh" "Fish" ]);

        tmux = {
          enable = true;
        };

        bash = {
          # This does not install bash but has home-manager control .bashrc and friends
          # Bash has some really weird behaviour with non-login and non-interactive shells, particularly around which
          # of profile and bashrc are loaded when. This causes issues with PATH not being set correctly for
          # non-interactive SSH...
          enable = mkDefault true;
          initExtra =
          ''
            flake-src() {
              cd "$(nix eval "''${@:2}" --impure --raw --expr "builtins.getFlake \"$1\"")"
            }
          '';
          shellAliases = {
            hm = "home-manager";
          };
        };

        fish = {
          enable = mkDefault true;
          interactiveShellInit =
            # TODO: Pull request?
            (optionalString config.programs.starship.enable
            ''
              # Adapted from https://github.com/nix-community/home-manager/blob/0232fe1b75e6d7864fd82b5c72f6646f87838fc3/modules/programs/starship.nix#L113
              # linux is the VTTY, which doesn't seem to have a suitable font for starship
              if test "$TERM" != "dumb" -a "$TERM" != "linux" -a \( -z "$INSIDE_EMACS"  -o "$INSIDE_EMACS" = "vterm" \)
                eval (${config.home.profileDirectory}/bin/starship init fish)
              end
            '');
          functions = {
            # Silence the default greeting
            fish_greeting = ":";
            flake-src = {
              description = "cd into a flake reference's source directory";
              body = ''cd (nix eval $argv[2..] --impure --raw --expr "builtins.getFlake \"$argv[1]\"")'';
            };
          };
          shellAbbrs = {
            hm = "home-manager";
            k = "kubectl";
          };
          shellAliases = {
            ip = "ip --color=auto";
            s = "kitty +kitten ssh";
          };
        };

        ssh = {
          enable = mkDefault true;
          matchBlocks = {
            nix-dev-vm = {
              user = "dev";
              hostname = "localhost";
              port = 2222;
              extraOptions = {
                StrictHostKeyChecking = "no";
                UserKnownHostsFile = "/dev/null";
              };
            };

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
          extraConfig =
            ''
              IdentityFile ~/.ssh/id_rsa
              IdentityFile ~/.ssh/netsoc
              IdentityFile ~/.ssh/borg
            '';
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
          file
          tree
          pwgen
          iperf3
          mosh
          wget
          hyx
          whois
          ldns
          minicom
          mtr
          ncdu
          jq
          yq-go
        ];

        sessionVariables = {
          EDITOR = "vim";
        };

        language.base = mkDefault "en_IE.UTF-8";
      };
    }
    (mkIf (config.my.isStandalone || !args.osConfig.home-manager.useGlobalPkgs) {
      # Note: If globalPkgs mode is on, then these will be overridden by the NixOS equivalents of these options
      nixpkgs = {
        overlays = [
          inputs.deploy-rs.overlay
          inputs.boardie.overlays.default
          inputs.nixGL.overlays.default
        ];
        config = {
          allowUnfree = true;
        };
      };
      nix = {
        registry = {
          pkgs = {
            to = {
              type = "path";
              path = "${pkgsFlake}";
            };
            exact = true;
          };
        };
        settings = with lib.my.c.nix; {
          extra-substituters = cache.substituters;
          extra-trusted-public-keys = cache.keys;
        };
      };
    })
    (mkIf config.my.isStandalone {
      my = {
        ssh.authKeys.files = [ lib.my.c.sshKeyFiles.me ];
      };

      nix.package = mkIf (versionAtLeast config.home.stateVersion "22.05") pkgs.nix;

      fonts.fontconfig.enable = true;

      home = {
        packages = with pkgs; [
          pkgs'.mine.nix
        ];

        # Without this, we are at the mercy of whatever version of nix is in $PATH...
        # TODO: Is this the right thing to do?
        extraActivationPath = [
          config.nix.package
        ];
      };
    })
    (mkIf pkgs.stdenv.isLinux (mkMerge [
      {
        home = {
          packages = with pkgs; [
            iputils
            traceroute
          ];
        };
      }
      (mkIf (config.my.isStandalone && config.programs.fish.enable && config.my.fishCompletionsFrequency != null) {
        systemd.user = {
          services.fish-update-completions = {
            Unit.Description = "fish completions update";

            Service = {
              Type = "oneshot";
              ExecStart = "${config.programs.fish.package}/bin/fish -c fish_update_completions";
            };
          };

          timers.fish-update-completions = {
            Unit.Description = "fish completions update timer";

            Timer = {
              OnCalendar = config.my.fishCompletionsFrequency;
              Persistent = true;
              Unit = "fish-update-completions.service";
            };

            Install.WantedBy = [ "timers.target" ];
          };
        };
      })
    ]))
    (mkIf (pkgs.stdenv.isDarwin && config.my.isStandalone) {
      home = {
        # No targets.genericLinux equivalent apparently
        sessionVariablesExtra =
          ''
            . "${config.nix.package}/etc/profile.d/nix.sh"
          '';
        packages = with pkgs; [
          cacert
        ];
      };
    })
  ];
}
