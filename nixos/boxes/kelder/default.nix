{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.kelder) domain prefixes;
in
{
  imports = [ ./containers ];

  nixos.systems.kelder = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    assignments = {
      estuary = {
        ipv4 ={
          address = net.cidr.host 0 lib.my.c.colony.prefixes.vip2;
          mask = 32;
          gateway = null;
        };
      };
      ctrs = {
        name = "kelder-ctrs";
        inherit domain;
        ipv4 = {
          address = net.cidr.host 1 prefixes.ctrs.v4;
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
        dnatMark = 123;
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
            kernelPackages = lib.my.c.kernel.lts pkgs;
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
            groups = with lib.my.c.kelder.groups; {
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
            smartd = {
              enable = true;
              autodetect = true;
              extraOptions = [ "-A /var/log/smartd/" "--interval=600" ];
            };
            netdata = {
              enable = true;
            };

            samba = {
              enable = true;
              enableNmbd = true;
              shares = {
                storage = {
                  path = "/mnt/storage";
                  browseable = "yes";
                  writeable = "yes";
                  "create mask" = "0664";
                  "directory mask" = "0775";
                };
              };
            };
            samba-wsdd.enable = true;

            minecraft-server = {
              enable = true;
              package = pkgs.minecraftServers.vanilla-1-19;
              declarative = true;
              eula = true;
              whitelist = {
                devplayer0 = "6d7d971b-ce10-435b-85c5-c99c0d8d288c";
              };
              serverProperties = {
                motd = "Simpcraft";
                white-list = true;
              };
            };
          };

          networking = {
            inherit domain;
          };

          system.nixos.distroName = "KelderOS";

          systemd = {
            tmpfiles.rules = [
              "d /var/log/smartd 0755 root root"
            ];

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
                        Endpoint = "estuary-vm.${lib.my.c.colony.domain}:${toString lib.my.c.kelder.vpn.port}";
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
                  address = with assignments.estuary; [
                    (with ipv4; "${address}/${toString mask}")
                  ];
                  routingPolicyRules = map (r: { routingPolicyRuleConfig = r; }) [
                    {
                      Family = "both";
                      SuppressPrefixLength = 0;
                      Table = "main";
                      Priority = 100;
                    }

                    {
                      From = assignments.estuary.ipv4.address;
                      Table = vpnTable;
                      Priority = 100;
                    }
                    {
                      FirewallMark = dnatMark;
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
              ddns-update = {
                description = "DNS update script";
                after = [ "network.target" ];
                path = [
                  (pkgs.python3.withPackages (ps: [ ps.cloudflare ]))
                  pkgs.iproute2
                ];
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = ''${./dns_update.py} -k ${config.age.secrets."kelder/ddclient-cloudflare.key".path} hentai.engineer kelder-local.hentai.engineer et1g0'';
                };
                wantedBy = [ "multi-user.target" ];
              };
            };
            timers = {
              ddns-update = {
                description = "Periodically update DNS";
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnBootSec = "10min";
                  OnUnitInactiveSec = "10min";
                };
              };
            };
          };

          my = {
            server.enable = true;
            user = {
              config.name = "kontent";
            };

            #deploy.node.hostname = "10.16.9.21";
            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOFvUdJshXkqmchEgkZDn5rgtZ1NO9vbd6Px+S6YioWi";
              files = {
                "kelder/estuary-wg.key" = {
                  owner = "systemd-network";
                };
                "kelder/ddclient-cloudflare.key" = {};
              };
            };

            firewall = {
              trustedInterfaces = [ "ctrs" ];
              tcp.allowed = [ 25565 ];
              udp.allowed = [ 25565 ];
              nat = {
                enable = true;
                externalInterface = "{ et1g0, estuary }";
                forwardPorts = [
                  {
                    port = "http";
                    dst = allAssignments.kelder-spoder.internal.ipv4.address;
                  }
                  {
                    port = "https";
                    dst = allAssignments.kelder-spoder.internal.ipv4.address;
                  }
                ];
              };
              extraRules = ''
                table inet filter {
                  chain input {
                    iifname et1g0 tcp dport { 139, 445, 5357 } accept
                    iifname et1g0 udp dport { 137, 138, 3702 } accept
                  }
                }
                table inet raw {
                  chain prerouting {
                    type filter hook prerouting priority mangle; policy accept;
                    ip daddr ${assignments.estuary.ipv4.address} ct state new ct mark set ${toString dnatMark}
                    ip saddr ${lib.my.c.kelder.prefixes.all.v4} ct mark != 0 meta mark set ct mark
                  }
                  chain output {
                    type filter hook output priority mangle; policy accept;
                    ct mark != 0 meta mark set ct mark
                  }
                }
                table inet nat {
                  chain postrouting {
                    ip saddr ${lib.my.c.kelder.prefixes.all.v4} oifname et1g0 masquerade
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
                kelder-spoder = {
                  bindMounts = {
                    "/mnt/storage".readOnly = false;
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
