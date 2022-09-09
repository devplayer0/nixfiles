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
          opengl.extraPackages = with pkgs; [
            intel-media-driver
          ];
          bluetooth.enable = true;
        };

        boot = {
          loader = {
            efi.canTouchEfiVariables = true;
            timeout = 10;
          };
          kernelPackages = pkgs.linuxKernel.packages.linux_5_19;
          kernelModules = [ "kvm-intel" ];
          kernelParams = [ "intel_iommu=on" ];
          initrd = {
            availableKernelModules = [ "nvme" "xhci_pci" "usb_storage" "usbhid" "thunderbolt" ];
            luks = {
              reusePassphrases = true;
              devices = {
                persist = {
                  device = "/dev/disk/by-uuid/27840c6f-445c-4b95-8c39-e69d07219f33";
                  allowDiscards = true;
                  preLVM = false;
                };
                home = {
                  device = "/dev/disk/by-uuid/c16c5038-7883-42c3-960a-a085a99364eb";
                  allowDiscards = true;
                  preLVM = false;
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
          lvm = {
            boot.thin.enable = true;
            dmeventd.enable = true;
          };
          fstrim.enable = true;
          tlp = {
            enable = true;
            settings = {
              CPU_BOOST_ON_BAT = 0;
              CPU_SCALING_GOVERNOR_ON_BATTERY = "powersave";
              START_CHARGE_THRESH_BAT0 = 90;
              STOP_CHARGE_THRESH_BAT0 = 97;
              RUNTIME_PM_ON_BAT = "auto";
            };
          };

          resolved = {
            enable = true;
            extraConfig = mkForce "";
          };

          fprintd.enable = true;
          blueman.enable = true;
        };

        networking = {
          networkmanager = {
            enable = true;
            dns = "systemd-resolved";
            wifi = {
              backend = "wpa_supplicant";
            };
            extraConfig = ''
              [main]
              no-auto-default=*
            '';
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

        systemd = {
          services = {
            systemd-networkd-wait-online.enable = false;
          };

          network = {
            links = {
              "10-wifi" = {
                matchConfig.MACAddress = "8c:f8:c5:55:96:1e";
                linkConfig.Name = "wifi";
              };
            };
          };
        };

        my = {
          user = {
            tmphome = false;
            homeConfig = {
              services = {
                network-manager-applet.enable = true;
              };

              home = {
                packages = with pkgs; [
                  spotify
                ];
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
                gui.standalone = true;
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
