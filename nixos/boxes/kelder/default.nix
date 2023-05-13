{ lib, ... }: {
  nixos.systems.kelder = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    configuration = { lib, pkgs, modulesPath, config, systems, assignments, allAssignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;
      in
      {
        imports = [ ./boot.nix ];

        config = {
          hardware = {
            enableRedistributableFirmware = true;
            cpu = {
              intel.updateMicrocode = true;
            };
          };

          boot = {
            loader = {
              efi.canTouchEfiVariables = true;
              timeout = 5;
            };
            kernelPackages = pkgs.linuxKernel.packages.linux_6_1;
            kernelModules = [ "kvm-intel" ];
            kernelParams = [ "intel_iommu=on" ];
            initrd = {
              availableKernelModules = [ "xhci_pci" "nvme" "ahci" "usbhid" "usb_storage" "sd_mod" ];
              kernelModules = [ "dm-snapshot" "pcspkr" ];
            };
          };

          fileSystems = {
            "/boot" = {
              device = "/dev/disk/by-partuuid/cba48ae7-ad2f-1a44-b5c7-dcbb7bebf8c4";
              fsType = "vfat";
            };
            "/nix" = {
              device = "/dev/ssd/nix";
              fsType = "ext4";
            };
            "/persist" = {
              device = "/dev/ssd/persist";
              fsType = "ext4";
              neededForBoot = true;
            };
          };

          services = {
            fstrim.enable = true;
            lvm = {
              boot.thin.enable = true;
              dmeventd.enable = true;
            };
            getty = {
              greetingLine = ''Welcome to ${config.system.nixos.distroName} ${config.system.nixos.label} (\m) - \l'';
              helpLine = "\nCall Jack for help.";
            };
          };

          networking = {
            domain = lib.my.kelder.domain;
          };

          system.nixos.distroName = "KelderOS";

          systemd = {
            network = {
              links = {
                "10-et1g0" = {
                  matchConfig.MACAddress = "74:d4:35:e9:a1:73";
                  linkConfig.Name = "et1g0";
                };
              };
              networks = {
                "50-lan" = {
                  matchConfig.Name = "et1g0";
                  DHCP = "yes";
                };
              };
            };
          };

          my = {
            user = {
              config.name = "kontent";
            };

            #deploy.generate.system.mode = "boot";
            deploy.node.hostname = "10.16.9.21";
            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOFvUdJshXkqmchEgkZDn5rgtZ1NO9vbd6Px+S6YioWi";
            };

            server.enable = true;
          };
        };
      };
  };
}
