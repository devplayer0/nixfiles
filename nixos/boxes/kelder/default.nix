{ lib, ... }: {
  imports = [ ./containers ];

  nixos.systems.kelder = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    assignments = {
      ctrs = {
        name = "kelder-ctrs";
        domain = lib.my.kelder.domain;
        ipv4 = {
          address = "${lib.my.kelder.start.ctrs.v4}1";
          gateway = null;
        };
      };
    };

    configuration = { lib, pkgs, modulesPath, config, systems, assignments, allAssignments, ... }:
      let
        inherit (builtins) mapAttrs;
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;

        vpnTable = 51820;
      in
      {
        imports = [ ./boot.nix ./nginx.nix ];

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
              device = "/dev/disk/by-uuid/0aab0249-700f-4856-8e16-7be3695295f5";
              fsType = "ext4";
            };
            "/persist" = {
              device = "/dev/disk/by-uuid/8c01e6b5-bdbf-4e5c-a33b-8693959ebe8a";
              fsType = "ext4";
              neededForBoot = true;
            };

            "/mnt/storage" = {
              device = "/dev/disk/by-partuuid/58a2e2a8-0321-ed4e-9eed-0ac7f63acb26";
              fsType = "ext4";
            };
          };

          users = {
            groups = with lib.my.kelder.groups; {
              storage.gid = storage;
              media.gid = media;
            };
            users = {
              "${config.my.user.config.name}".extraGroups = [ "storage" "media" ];
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
                "25-ctrs".netdevConfig = {
                  Name = "ctrs";
                  Kind = "bridge";
                };

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
                "80-ctrs" = mkMerge [
                  (networkdAssignment "ctrs" assignments.ctrs)
                  {
                    networkConfig.IPv6AcceptRA = mkForce false;
                  }
                ];
                "95-estuary" = {
                  matchConfig.Name = "estuary";
                  address = [ "${lib.my.kelder.start.vpn.v4}2/30" ];
                  routingPolicyRules = map (r: { routingPolicyRuleConfig = r; }) [
                    {
                      From = "${lib.my.kelder.start.vpn.v4}2";
                      Table = vpnTable;
                      Priority = 100;
                    }
                  ];
                };
              };
            };

            services = {
              "systemd-nspawn@kelder-acquisition".serviceConfig.DeviceAllow = [
                # For hardware acceleration in Jellyfin
                "char-drm rw"
              ];
            };
          };

          my = {
            server.enable = true;
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

            firewall = {
              trustedInterfaces = [ "ctrs" ];
              nat = {
                enable = true;
                externalInterface = "et1g0";
              };
              extraRules = ''
                table inet nat {
                  chain postrouting {
                    ip saddr ${lib.my.kelder.prefixes.all.v4} oifname et1g0 masquerade
                  }
                }
              '';
            };

            containers.instances =
            let
              instances = {
                kelder-acquisition = {
                  bindMounts = {
                    "/dev/dri".readOnly = false;
                    "/mnt/media" = {
                      hostPath = "/mnt/storage/media";
                      readOnly = false;
                    };
                  };
                };
              };
            in
            mkMerge [
              instances
              (mapAttrs (n: i: {
                networking.bridge = "ctrs";
              }) instances)
            ];
          };
        };
      };
  };
}
