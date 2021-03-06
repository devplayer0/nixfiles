{ lib, pkgs, pkgs', inputs, config, ... }:
let
  inherit (lib) mkIf mkDefault mkMerge;
  inherit (lib.my) mkBoolOpt' dummyOption;
in
{
  options = with lib.types; {
    my = {
      ssh = {
        strictModes = mkBoolOpt' true
          ("Specifies whether sshd(8) should check file modes and ownership of the user's files and home directory "+
          "before accepting login.");
      };
    };
  };

  imports = [
    inputs.impermanence.nixosModule
    inputs.agenix.nixosModules.age
  ];

  config = mkMerge [
    {
      system = {
        stateVersion = "22.05";
        configurationRevision = with inputs; mkIf (self ? rev) self.rev;
      };

      home-manager = {
        # Installs packages in the system config instead of in the local profile on activation
        useUserPackages = mkDefault true;
      };

      users = {
        mutableUsers = false;
      };

      security = {
        sudo.enable = mkDefault false;
        doas = {
          enable = mkDefault true;
          wheelNeedsPassword = mkDefault false;
        };
      };

      nix = {
        package = pkgs'.mine.nix;
        settings = {
          trusted-users = [ "@wheel" ];
          experimental-features = [ "nix-command" "flakes" "ca-derivations" ];
          substituters = [
            "https://nix-cache.nul.ie"
            "https://cache.nixos.org"
          ];
          trusted-public-keys = lib.my.nix.cacheKeys;
        };
        registry = {
          pkgs = {
            to = {
              type = "path";
              path = "${pkgs.path}";
            };
            exact = true;
          };
        };
        gc = {
          options = mkDefault "--max-freed $((8 * 1024**3))";
          automatic = mkDefault true;
        };
      };
      nixpkgs = {
        overlays = [
          inputs.deploy-rs.overlay
        ];
        config = {
          allowUnfree = true;
        };
      };

      documentation = {
        enable = mkDefault true;
        nixos = {
          enable = mkDefault true;
          options.warningsAreErrors = mkDefault false;
        };
      };

      time.timeZone = mkDefault "Europe/Dublin";

      boot = {
        # Use latest LTS release by default
        kernelPackages = mkDefault pkgs.linuxKernel.packages.linux_5_15;
        kernel = {
          sysctl = {
            "net.ipv6.route.max_size" = mkDefault 16384;
          };
        };
        loader = {
          efi = {
            efiSysMountPoint = mkDefault "/boot";
            # Should generally be enough with just /EFI/BOOT/BOOTX64.EFI in place
            canTouchEfiVariables = mkDefault false;
          };
          grub = {
            memtest86.enable = mkDefault true;
          };
          systemd-boot = {
            enable = mkDefault true;
            editor = mkDefault true;
            consoleMode = mkDefault "max";
            configurationLimit = mkDefault 10;
            memtest86.enable = mkDefault true;
          };
        };
      };

      environment.systemPackages = with pkgs; mkMerge [
        [
          bash-completion
          vim
        ]
        (mkIf config.services.netdata.enable [ netdata ])
      ];

      programs = {
        # This will enable generating completions at build time and prevent home-manager fish from generating them
        # locally
        fish.enable = mkDefault true;
        # TODO: This is expecting to look up the channel for the database...
        command-not-found.enable = mkDefault false;
      };

      services = {
        kmscon = {
          # As it turns out, kmscon hasn't been updated in years and has some bugs...
          enable = mkDefault false;
          hwRender = mkDefault true;
          extraOptions = "--verbose";
          extraConfig =
            ''
              font-name=SauceCodePro Nerd Font Mono
            '';
        };

        openssh = {
          enable = mkDefault true;
          extraConfig = ''StrictModes ${if config.my.ssh.strictModes then "yes" else "no"}'';
          permitRootLogin = mkDefault "no";
          passwordAuthentication = mkDefault false;
        };

        netdata = {
          config = {
            global = {
              "memory mode" = "dbengine";
              "page cache size" = 32;
              "dbengine multihost disk space" = 256;
            };
            "plugin:cgroups" = {
              "cgroups to match as systemd services" =
                " /system.slice/system-*.slice/*.service !/system.slice/*/*.service /system.slice/*.service";
            };
          };
          configDir = {
            "go.d.conf" = mkDefault (pkgs.writeText "netdata-go.d.conf" ''
              modules:
                systemdunits: yes
            '');

            "go.d/systemdunits.conf" = mkDefault (pkgs.writeText "netdata-systemdunits.conf" ''
              jobs:
                - name: service-units
                  include:
                    - '*.service'

                - name: socket-units
                  include:
                    - '*.socket'
            '');
          };
        };
      };

      systemd = {
        services = {
          netdata = mkIf config.services.netdata.enable {
            # python.d plugin script does #!/usr/bin/env bash
            path = with pkgs; [ bash ];
          };
        };
      };
    }
    (mkIf config.services.kmscon.enable {
      fonts.fonts = with pkgs; [
        (nerdfonts.override {
          fonts = [ "SourceCodePro" ];
        })
      ];
    })
  ];

  meta.buildDocsInSandbox = false;
}
