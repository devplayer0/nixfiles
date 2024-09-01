{ lib, ... }:
let
  inherit (lib.my) net nft;
  inherit (lib.my.c.colony) domain prefixes firewallForwards;
in
{
  imports = [ ./containers ];

  nixos.systems.shill = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      routing = {
        name = "shill-vm-routing";
        inherit domain;
        ipv4.address = net.cidr.host 2 prefixes.vms.v4;
      };
      internal = {
        name = "shill-vm";
        altNames = [ "ctr" ];
        inherit domain;
        ipv4 = {
          address = net.cidr.host 1 prefixes.vip1;
          mask = 32;
          gateway = null;
          genPTR = false;
        };
        ipv6 = {
          iid = "::2";
          address = net.cidr.host 2 prefixes.vms.v6;
        };
      };
      ctrs = {
        name = "shill-vm-ctrs";
        inherit domain;
        ipv4 = {
          address = net.cidr.host 1 prefixes.ctrs.v4;
          gateway = null;
        };
        ipv6.address = net.cidr.host 1 prefixes.ctrs.v6;
      };
    };

    configuration = { lib, pkgs, modulesPath, config, assignments, allAssignments, ... }:
      let
        inherit (builtins) mapAttrs;
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [
          "${modulesPath}/profiles/qemu-guest.nix"

          ./containers-ext.nix
        ];

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

              "/mnt/media" = {
                device = "/dev/disk/by-label/media";
                fsType = "ext4";
              };
              "/mnt/minio" = {
                device = "/dev/disk/by-label/minio";
                fsType = "xfs";
              };
              "/mnt/nix-cache" = {
                device = "/dev/disk/by-label/nix-cache";
                fsType = "ext4";
              };
            };

            nix.settings = {
              # Exclude S3 cache that we're right next to
              substituters = mkForce [ "https://cache.nixos.org" ];
            };

            services = {
              fstrim = lib.my.c.colony.fstrimConfig;
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
                        ipv6PrefixConfig.Prefix = prefixes.ctrs.v6;
                      }
                    ];
                    routes = map (r: { routeConfig = r; }) [
                      {
                        Destination = lib.my.c.tailscale.prefix.v4;
                        Gateway = allAssignments.waffletail.internal.ipv4.address;
                      }
                      {
                        Destination = lib.my.c.tailscale.prefix.v6;
                        Gateway = allAssignments.waffletail.internal.ipv6.address;
                      }

                      {
                        Destination = prefixes.qclk.v4;
                        Gateway = allAssignments.qclk.internal.ipv4.address;
                      }
                    ];
                  }
                ];
              };
            };

            my = {
              secrets.key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ6bc1pQCYalLXdB4X+7kFXtkTdFalbH5rchjuYj2ceU";
              server.enable = true;

              firewall = {
                tcp.allowed = [ 19999 ];
                trustedInterfaces = [ "ctrs" ];
                nat.forwardPorts."${allAssignments.estuary.internal.ipv4.address}" = firewallForwards allAssignments;
                extraRules = ''
                  table inet filter {
                    chain forward {
                      # Trust that the outer firewall has done the filtering!
                      iifname vms oifname ctrs accept
                    }
                  }
                  table inet nat {
                    # Hack to fix our NAT situation with internal routing
                    # We need to snat to our public IP, otherwise on the return path from e.g. middleman it will
                    # try to forward packet directly with its own IP, bypassing our carefully crafted DNAT...
                    chain ${nft.dnatChain allAssignments.estuary.internal.ipv4.address} {
                      ct mark set 0x1337
                    }
                    chain postrouting {
                      ct mark 0x1337 snat ip to ${assignments.internal.ipv4.address}
                    }
                  }
                '';
              };

              containers.instances =
              let
                instances = {
                  middleman = {
                    bindMounts = {
                      "/mnt/media" = {};
                    };
                  };
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
                      "/mnt/nix-cache".readOnly = false;
                    };
                  };
                  toot = {};
                  waffletail = {};
                  qclk = {};
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
