{ lib, ... }: {
  nixos.systems.castle = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    configuration = { lib, pkgs, modulesPath, config, systems, assignments, allAssignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;
      in
      {
        hardware = {
          enableRedistributableFirmware = true;
          cpu = {
            amd.updateMicrocode = true;
          };
          opengl.extraPackages = with pkgs; [
            intel-media-driver
          ];
          bluetooth.enable = true;
        };

        boot = {
          loader = {
            efi.canTouchEfiVariables = false;
            timeout = 10;
          };
          kernelPackages = pkgs.linuxKernel.packages.linux_6_2;
          kernelModules = [ "kvm-amd" ];
          kernelParams = [ "amd_iommu=on" "amd_pstate=passive" ];
          kernelPatches = [
            # {
            #   # https://gitlab.freedesktop.org/drm/amd/-/issues/2354
            #   name = "drm-amd-display-fix-flickering-caused-by-S-G-mode";
            #   patch = ./0001-drm-amd-display-fix-flickering-caused-by-S-G-mode.patch;
            # }
          ];
          initrd = {
            availableKernelModules = [ "thunderbolt" "xhci_pci" "nvme" "ahci" "usbhid" "usb_storage" "sd_mod" ];
          };
        };

        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-partuuid/8ce4248a-3ee4-f44f-801f-064a628b4d6e";
            fsType = "vfat";
          };
          "/nix" = {
            device = "/dev/disk/by-partuuid/2da23a1d-2daf-d943-b91e-fc175f3dad07";
            fsType = "ext4";
          };

          "/persist" = {
            device = "/dev/disk/by-partuuid/f4c80d4f-a022-e941-b5d1-fe2e65e444b9";
            fsType = "ext4";
            neededForBoot = true;
          };
          "/home" = {
            device = "/dev/disk/by-partuuid/992a93cf-6c9c-324b-b0ce-f8eb2d1ce10d";
            fsType = "ext4";
          };
        };

        security = { };

        services = {
          hardware = {
            bolt.enable = true;
          };

          lvm = {
            boot.thin.enable = true;
            dmeventd.enable = true;
          };
          fstrim.enable = true;

          resolved = {
            enable = true;
            extraConfig = mkForce "";
            dnssec = "false";
          };

          blueman.enable = true;
        };

        networking = {
          domain = "h.${lib.my.pubDomain}";
          firewall.enable = false;
        };

        environment.systemPackages = with pkgs; [
          dhcpcd
          pciutils
          usbutils
          lm_sensors
          linuxPackages.cpupower
        ];
        environment.etc = {
          "pipewire/pipewire.conf.d/sample-size.conf".text = ''
            context.properties = {
              default.clock.quantum = 128
              default.clock.max-quantum = 128
            }
          '';
        };

        nix = {
          gc.automatic = false;
        };

        systemd = {
          network = {
            wait-online.enable = false;
            links = {
              "10-et2.5g" = {
                matchConfig.MACAddress = "c8:7f:54:6e:17:0f";
                linkConfig.Name = "et2.5g";
              };
              "11-et10g" = {
                matchConfig.MACAddress = "c8:7f:54:6e:15:af";
                linkConfig.Name = "et10g";
              };
              "12-et100g" = {
                matchConfig.MACAddress = "24:8a:07:a8:fe:3a";
                linkConfig.Name = "et100g";
              };
            };
            networks = {
              "50-lan" = {
                matchConfig.Name = "et2.5g";
                DHCP = "yes";
              };
            };
          };
        };

        my = {
          tmproot.size = "24G";

          user = {
            config.extraGroups = [ "input" ];

            tmphome = false;
            homeConfig = {
              services = { };

              home = {
                packages = with pkgs; [
                  jacktrip
                  qpwgraph
                  (writeShellScriptBin "boardie" ''
                    exec pw-jack ${pkgs.boardie}/bin/boardie "$@"
                  '')
                ];
              };

              services = {
                blueman-applet.enable = true;
              };

              wayland.windowManager.sway = {
                config = {
                  output = {
                    HDMI-A-1 = {
                      transform = "270";
                      position = "0 0";
                    };
                    DP-1 = {
                      mode = "2560x1440@170Hz";
                      subpixel = "bgr";
                      position = "1440 560";
                    };
                    DP-2.position = "4000 560";
                  };
                };
              };

              my = {
                gui.standalone = true;
              };
            };
          };

          #deploy.generate.system.mode = "boot";
          deploy.node.hostname = "castle.box.${config.networking.domain}";
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMlVuTzKObeaUuPocCF41IO/8X+443lzUJLuCIclt2vr";
          };

          firewall = {
            enable = false;
          };

          gui.enable = true;
        };
      };
  };
}
