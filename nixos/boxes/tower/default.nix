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
        };

        boot = {
          loader.efi.canTouchEfiVariables = true;
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

        console.keyMap = "uk";

        services = {
          lvm = {
            boot.thin.enable = true;
            dmeventd.enable = true;
          };
          fstrim.enable = true;

          resolved = {
            enable = true;
            extraConfig = mkForce "";
          };
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
          };

          #deploy.generate.system.mode = "boot";
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOU+UxJh8PZoiXV+0CRumv9Xsk6Fks4YMYRZcThmaJkB";
          };

          firewall = {
            enable = true;
          };
        };
      };
  };
}
