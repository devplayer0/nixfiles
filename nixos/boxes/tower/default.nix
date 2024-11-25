{ lib, ... }: {
  nixos.systems.tower = {
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
            intel.updateMicrocode = true;
          };
          graphics.extraPackages = with pkgs; [
            intel-media-driver
          ];
          bluetooth.enable = true;
        };

        boot = {
          loader = {
            efi.canTouchEfiVariables = true;
            timeout = 10;
          };
          kernelPackages = lib.my.c.kernel.latest pkgs;
          kernelModules = [ "kvm-intel" ];
          kernelParams = [ "intel_iommu=on" ];
          initrd = {
            availableKernelModules = [ "nvme" "xhci_pci" "usb_storage" "usbhid" "thunderbolt" ];
            luks = {
              devices = {
                persist = {
                  device = "/dev/disk/by-uuid/27840c6f-445c-4b95-8c39-e69d07219f33";
                  allowDiscards = true;
                };
                home = {
                  device = "/dev/disk/by-uuid/c16c5038-7883-42c3-960a-a085a99364eb";
                  allowDiscards = true;
                };
              };
            };
          };
        };

        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-partuuid/66bc15d3-83dd-ea47-9753-3fb88eab903f";
            fsType = "vfat";
          };
          "/nix" = {
            device = "/dev/disk/by-uuid/cd597ff0-ca72-4a13-84c8-91b9c09e0a29";
            fsType = "ext4";
          };

          "/persist" = {
            device = "/dev/disk/by-uuid/1e9b6a54-bd8d-4ff3-8c06-7b214a35db57";
            fsType = "ext4";
            neededForBoot = true;
          };
          "/home" = {
            device = "/dev/disk/by-uuid/5dc99dd6-0d05-45b3-acb6-03c29a9b9388";
            fsType = "ext4";
          };
        };

        security = {
          doas = {
            # Fingerprint auth :)
            wheelNeedsPassword = true;
            extraRules = [ { groups = [ "wheel" ]; persist = true; } ];
          };
        };

        console.keyMap = "uk";

        services = {
          hardware = {
            bolt.enable = true;
          };

          lvm = {
            boot.thin.enable = true;
            dmeventd.enable = true;
          };
          fstrim.enable = true;
          tlp = {
            enable = true;
            settings = {
              CPU_BOOST_ON_BAT = 1;
              CPU_BOOST_ON_AC = 1;
              CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
              CPU_SCALING_GOVERNOR_ON_AC = "performance";
              START_CHARGE_THRESH_BAT0 = 90;
              STOP_CHARGE_THRESH_BAT0 = 97;
              RUNTIME_PM_ON_BAT = "auto";
            };
          };

          resolved = {
            enable = true;
            extraConfig = mkForce "";
            dnssec = "false";
          };

          fprintd.enable = true;
          blueman.enable = true;

          tailscale = {
            enable = true;
            openFirewall = true;
          };
        };

        programs = {
          steam.enable = true;
          wireshark = {
            enable = true;
            package = pkgs.wireshark-qt;
          };
        };

        networking = {
          networkmanager = {
            enable = true;
            dns = "systemd-resolved";
            wifi = {
              backend = "wpa_supplicant";
            };
            settings = {
              main.no-auto-default = "*";
            };
          };
        };

        environment.systemPackages = with pkgs; [
          dhcpcd
          pciutils
          usbutils
          lm_sensors
          linuxPackages.cpupower
          brightnessctl
        ];

        nix = {
          gc.automatic = false;
        };

        systemd = {
          network = {
            wait-online.enable = false;
            links = {
              "10-wifi" = {
                matchConfig.MACAddress = "8c:f8:c5:55:96:1e";
                linkConfig.Name = "wifi";
              };
            };
          };
        };

        my = {
          tmproot.size = "8G";

          user = {
            tmphome = false;
            homeConfig = {
              services = {
                network-manager-applet.enable = true;
              };

              home = {
                packages = with pkgs; [ ];
              };

              programs = {
                fish = {
                  shellAbbrs = {
                    tsup = "doas tailscale up --login-server=https://hs.nul.ie --accept-routes";
                  };
                };
              };

              services = {
                blueman-applet.enable = true;
              };

              wayland.windowManager.sway = {
                config = {
                  input."1:1:AT_Translated_Set_2_keyboard".xkb_layout = "ie";
                  output.eDP-1.scale = "1";
                };
              };

              my = {
                gui = {
                  standalone = true;
                  manageGraphical = true;
                };
              };
            };
          };

          #deploy.generate.system.mode = "boot";
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOU+UxJh8PZoiXV+0CRumv9Xsk6Fks4YMYRZcThmaJkB";
          };

          firewall = {
            enable = true;
          };

          gui.enable = true;
        };
      };
  };
}
