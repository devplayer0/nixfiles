{ lib, ... }:
let
  inherit (builtins) mapAttrs;
  inherit (lib.my) net;
  inherit (lib.my.c.colony) domain prefixes;
in
{
  nixos.systems.whale2 = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      routing = {
        name = "whale-vm-routing";
        inherit domain;
        ipv4.address = net.cidr.host 3 prefixes.vms.v4;
      };
      internal = {
        name = "whale-vm";
        altNames = [ "oci" ];
        inherit domain;
        ipv4 = {
          address = net.cidr.host 2 prefixes.vip1;
          mask = 32;
          gateway = null;
          genPTR = false;
        };
        ipv6 = {
          iid = "::3";
          address = net.cidr.host 3 prefixes.vms.v6;
        };
      };
      oci = {
        name = "whale-vm-oci";
        inherit domain;
        ipv4 = {
          address = net.cidr.host 1 prefixes.oci.v4;
          gateway = null;
        };
        ipv6.address = net.cidr.host 1 prefixes.oci.v6;
      };
    };

    extraAssignments = mapAttrs (n: i: {
      internal = {
        name = n;
        inherit domain;
        ipv4.address = net.cidr.host i prefixes.oci.v4;
        ipv6.address = net.cidr.host i prefixes.oci.v6;
      };
    }) {
      valheim-oci = 2;
      simpcraft-oci = 3;
      simpcraft-staging-oci = 4;
    };

    configuration = { lib, pkgs, modulesPath, config, assignments, allAssignments, ... }:
      let
        inherit (builtins) toJSON;
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [
          "${modulesPath}/profiles/qemu-guest.nix"

          ./valheim.nix
          ./minecraft
        ];

        config = mkMerge [
          {
            boot = {
              kernelParams = [ "console=ttyS0,115200n8" ];
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

              "/var/lib/containers" = {
                device = "/dev/disk/by-label/oci";
                fsType = "xfs";
                options = [ "pquota" ];
              };
            };

            services = {
              fstrim = lib.my.c.colony.fstrimConfig;
              netdata.enable = true;
            };

            virtualisation = {
              podman = {
                enable = true;
              };
              oci-containers = {
                backend = "podman";
              };
              containers.containersConf.settings.network = {
                network_backend = "netavark";
                firewall_driver = "none";
              };
            };

            environment = {
              etc = {
                "containers/networks/colony.json".text = toJSON {
                  name = "colony";
                  id = "0000000000000000000000000000000000000000000000000000000000000001";
                  driver = "bridge";
                  network_interface = "oci";
                  ipv6_enabled = true;
                  internal = false;
                  dns_enabled = false;
                  subnets = [
                    {
                      subnet = prefixes.oci.v4;
                      gateway = net.cidr.host 1 prefixes.oci.v4;
                    }
                    {
                      subnet = prefixes.oci.v6;
                      gateway = net.cidr.host 1 prefixes.oci.v6;
                    }
                  ];
                };
              };
            };

            systemd.network = {
              links = {
                "10-vms" = {
                  matchConfig.MACAddress = "52:54:00:d5:d9:c6";
                  linkConfig.Name = "vms";
                };
              };

              networks = {
                "80-vms" = mkMerge [
                  (networkdAssignment "vms" assignments.routing)
                  (networkdAssignment "vms" assignments.internal)
                ];
              };
            };

            my = {
              secrets.key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDBTIj1jVdknXLNNroMJfgy7S2cSUC/qgFdnaUopEUzZ";
              server.enable = true;

              firewall = {
                tcp.allowed = [ 19999 ];
                trustedInterfaces = [ "oci" ];
                extraRules = ''
                  table inet filter {
                    chain forward {
                      # Trust that the outer firewall has done the filtering!
                      iifname vms oifname oci accept
                    }
                  }
                '';
              };
            };
          }
        ];
      };
  };
}
