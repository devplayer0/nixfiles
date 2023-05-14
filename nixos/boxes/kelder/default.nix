{ lib, ... }: {
  nixos.systems.kelder = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    configuration = { lib, pkgs, modulesPath, config, systems, assignments, allAssignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;

        vpnTable = 51820;
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

          environment = {
            systemPackages = with pkgs; [
              wireguard-tools
            ];
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
              netdevs = {
                "30-estuary" = {
                  netdevConfig = {
                    Name = "estuary";
                    Kind = "wireguard";
                  };
                  wireguardConfig = {
                    PrivateKeyFile = config.age.secrets."kelder/estuary-wg.key".path;
                    RouteTable = vpnTable;
                  };
                  wireguardPeers = [
                    {
                      wireguardPeerConfig = {
                        PublicKey = "bP1XUNxp9i8NLOXhgPaIaRzRwi5APbam44/xjvYcyjU=";
                        Endpoint = "estuary-vm.${lib.my.colony.domain}:${toString lib.my.kelder.vpn.port}";
                        AllowedIPs = [ "0.0.0.0/0" ];
                        PersistentKeepalive = 25;
                      };
                    }
                  ];
                };
              };
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
                "95-estuary" = {
                  matchConfig.Name = "estuary";
                  address = [ "${lib.my.kelder.vpn.start}2/30" ];
                  routingPolicyRules = map (r: { routingPolicyRuleConfig = r; }) [
                    {
                      From = "${lib.my.kelder.vpn.start}2";
                      Table = vpnTable;
                      Priority = 100;
                    }
                  ];
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
              files = {
                "kelder/estuary-wg.key" = {
                  owner = "systemd-network";
                };
              };
            };

            server.enable = true;
          };
        };
      };
  };
}
