{ lib, pkgsFlake, pkgs, pkgs', self, inputs, config, ... }:
let
  inherit (lib) mkIf mkDefault mkMerge;
  inherit (lib.my) mkDefault';
in
{
  options = with lib.types; {
    my = { };
  };

  imports = [
    inputs.impermanence.nixosModule
    inputs.ragenix.nixosModules.age
    inputs.sharry.nixosModules.default
    inputs.copyparty.nixosModules.default
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
        channel.enable = false;
        settings = with lib.my.c.nix; {
          trusted-users = [ "@wheel" ];
          experimental-features = [ "nix-command" "flakes" "ca-derivations" ];
          extra-substituters = cache.substituters;
          extra-trusted-public-keys = cache.keys;
          connect-timeout = 5;
          fallback = true;
        };
        registry = {
          pkgs = {
            to = {
              type = "path";
              path = "${pkgsFlake}";
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
          inputs.deploy-rs.overlays.default
          inputs.sharry.overlays.default
          # TODO: Re-enable when borgthin is updated
          # inputs.borgthin.overlays.default
          inputs.boardie.overlays.default
          inputs.copyparty.overlays.default
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
      i18n.defaultLocale = "en_IE.UTF-8";

      boot = {
        # Use latest LTS release by default
        kernelPackages = mkDefault (lib.my.c.kernel.lts pkgs);
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

        initrd = {
          systemd = {
            enable = mkDefault true;
            emergencyAccess = mkDefault true;
          };
          services.lvm.enable = mkDefault true;
        };
      };
      system = {
        nixos = {
          distroName = mkDefault' "JackOS";
        };
      };

      environment.etc = {
        "nixos/flake.nix".source = "/run/nixfiles/flake.nix";
      };
      environment.systemPackages = with pkgs; mkMerge [
        [
          bash-completion
          git
          unzip
        ]
        (mkIf config.services.netdata.enable [ netdata ])
      ];

      programs = {
        # This will enable generating completions at build time and prevent home-manager fish from generating them
        # locally
        fish.enable = mkDefault true;
        # TODO: This is expecting to look up the channel for the database...
        command-not-found.enable = mkDefault false;
        vim = {
          enable = true;
          defaultEditor = true;
        };
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
        getty.greetingLine = mkDefault' ''<<< Welcome to ${config.system.nixos.distroName} ${config.system.nixos.label} (\m) - \l >>>'';

        openssh = {
          enable = mkDefault true;
          settings = {
            PermitRootLogin = mkDefault "no";
            PasswordAuthentication = mkDefault false;
            StrictModes = mkDefault true;
          };
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
        tmpfiles.rules = [
          "d /nix/tmp 0775 root nixbld 24h"
        ];
        services = {
          nix-daemon.environment.TMPDIR = "/nix/tmp";
          netdata = mkIf config.services.netdata.enable {
            # python.d plugin script does #!/usr/bin/env bash
            path = with pkgs; [ bash ];
          };

          nixfiles-mutable = {
            description = "Mutable nixfiles";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };

            path = with pkgs; [ util-linux ];
            script = ''
              nixfilesDir="${self}"

              mkdir -p /run/nixfiles{,/.rw,/.work}
              mount -t overlay overlay -o lowerdir="$nixfilesDir",upperdir=/run/nixfiles/.rw,workdir=/run/nixfiles/.work /run/nixfiles
              chmod -R u+w /run/nixfiles
            '';
            preStop = ''
              umount /run/nixfiles
              rm -rf /run/nixfiles
            '';

            wantedBy = [ "multi-user.target" ];
          };
        };
      };
    }
    (mkIf config.services.kmscon.enable {
      fonts.fonts = with pkgs; [
        nerd-fonts.sauce-code-pro
      ];
    })
  ];

  meta.buildDocsInSandbox = false;
}
