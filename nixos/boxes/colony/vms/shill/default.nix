{ lib, ... }: {
  imports = [ ./containers ];

  nixos.systems.shill = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "shill-vm";
        altNames = [ "ctr" ];
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.vms.v4}2";
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
        imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

        config = mkMerge [
          {
            boot = {
              kernelParams = [ "console=ttyS0,115200n8" ];
              # Stolen from nixos/modules/services/torrent/transmission.nix
              kernel.sysctl = {
                "net.core.rmem_max" = "4194304"; # 4MB
                "net.core.wmem_max" = "1048576"; # 1MB
                "net.ipv4.ip_local_port_range" = "16384 65535";
                "net.netfilter.nf_conntrack_generic_timeout" = 60;
                "net.netfilter.nf_conntrack_tcp_timeout_established" = 600;
                "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 1;
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
              "/mnt/media" = {
                device = "/dev/disk/by-label/media";
                fsType = "ext4";
              };
            };

            services = {
              netdata.enable = true;
            };

            systemd.network = {
              links = {
                "10-vms" = {
                  matchConfig.MACAddress = "52:54:00:85:b3:b1";
                  linkConfig.Name = "vms";
                };
              };
              netdevs."25-ctrs".netdevConfig = {
                Name = "ctrs";
                Kind = "bridge";
              };

              networks = {
                "80-vms" = networkdAssignment "vms" assignments.internal;
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

            my = {
              secrets.key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMWi6iEcpKdWPiHPgQEeVVKfB3yWNXQbXbr8IXYL+6Cw";
              server.enable = true;

              firewall = {
                tcp.allowed = [ 19999 ];
                trustedInterfaces = [ "vms" "ctrs" ];
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
