{ lib, ... }: {
  imports = [ ./containers ];

  nixos.systems.shill = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      routing = {
        name = "shill-vm-routing";
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.vms.v4}2";
      };
      internal = {
        name = "shill-vm";
        altNames = [ "ctr" ];
        domain = lib.my.colony.domain;
        ipv4 = {
          address = "${lib.my.colony.start.vip1}5";
          mask = 32;
          gateway = null;
          genPTR = false;
        };
        ipv6 = {
          iid = "::2";
          address = "${lib.my.colony.start.vms.v6}2";
        };
      };
      ctrs = {
        name = "shill-vm-ctrs";
        domain = lib.my.colony.domain;
        ipv4 = {
          address = "${lib.my.colony.start.ctrs.v4}1";
          gateway = null;
        };
        ipv6.address = "${lib.my.colony.start.ctrs.v6}1";
      };
    };

    configuration = { lib, pkgs, modulesPath, config, assignments, allAssignments, ... }:
      let
        inherit (builtins) mapAttrs;
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [ "${modulesPath}/profiles/qemu-guest.nix" ./hercules.nix ];

        config = mkMerge [
          {
            boot = {
              kernelParams = [ "console=ttyS0,115200n8" ];
              # Stolen from nixos/modules/services/torrent/transmission.nix
              kernel.sysctl = {
                "net.core.rmem_max" = 4194304; # 4MB
                "net.core.wmem_max" = 1048576; # 1MB
                "net.ipv4.ip_local_port_range" = "16384 65535";
                #"net.netfilter.nf_conntrack_generic_timeout" = 60;
                #"net.netfilter.nf_conntrack_tcp_timeout_established" = 600;
                #"net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 1;
                "net.netfilter.nf_conntrack_max" = 1048576;
              };
            };

            fileSystems = {
              "/boot" = {
                device = "/dev/disk/by-label/ESP";
                fsType = "vfat";
              };
              "/nix" = {
                device = "/dev/disk/by-label/nix";
                fsType = "ext4";
              };
              "/persist" = {
                device = "/dev/disk/by-label/persist";
                fsType = "ext4";
                neededForBoot = true;
              };
              # "/mnt/media" = {
              #   device = "/dev/disk/by-label/media";
              #   fsType = "ext4";
              # };
              "/mnt/minio" = {
                device = "/dev/disk/by-label/minio";
                fsType = "xfs";
              };
            };

            nix.settings = {
              # Exclude S3 cache that we're right next to
              substituters = mkForce [ "https://cache.nixos.org" ];
            };

            services = {
              fstrim.enable = true;
              netdata.enable = true;
            };

            systemd.network = {
              links = {
                "10-vms" = {
                  matchConfig.MACAddress = "52:54:00:27:3d:5c";
                  linkConfig.Name = "vms";
                };
              };
              netdevs."25-ctrs".netdevConfig = {
                Name = "ctrs";
                Kind = "bridge";
              };

              networks = {
                "80-vms" = mkMerge [
                  (networkdAssignment "vms" assignments.routing)
                  (networkdAssignment "vms" assignments.internal)
                ];
                "80-ctrs" = mkMerge [
                  (networkdAssignment "ctrs" assignments.ctrs)
                  {
                    networkConfig = {
                      IPv6AcceptRA = mkForce false;
                      IPv6SendRA = true;
                    };
                    ipv6SendRAConfig = {
                      DNS = [ allAssignments.estuary.base.ipv6.address ];
                      Domains = [ config.networking.domain ];
                    };
                    ipv6Prefixes = [
                      {
                        ipv6PrefixConfig.Prefix = lib.my.colony.prefixes.ctrs.v6;
                      }
                    ];
                  }
                ];
              };
            };

            systemd.services."systemd-nspawn@jackflix".enable = false;
            my = {
              secrets.key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ6bc1pQCYalLXdB4X+7kFXtkTdFalbH5rchjuYj2ceU";
              server.enable = true;

              firewall = {
                tcp.allowed = [ 19999 ];
                trustedInterfaces = [ "ctrs" ];
                extraRules = ''
                  table inet filter {
                    chain forward {
                      # Trust that the outer firewall has done the filtering!
                      iifname vms oifname ctrs accept
                    }
                  }
                '';
              };

              containers.instances =
              let
                instances = {
                  middleman = {};
                  vaultwarden = {};
                  colony-psql = {};
                  chatterbox = {};
                  jackflix = {
                    bindMounts = {
                      "/mnt/media".readOnly = false;
                    };
                  };
                  object = {
                    bindMounts = {
                      "/mnt/minio".readOnly = false;
                    };
                  };
                  toot = {};
                };
              in
              mkMerge [
                instances
                (mapAttrs (n: i: {
                  networking.bridge = "ctrs";
                }) instances)
              ];
            };
          }
        ];
      };
  };
}
