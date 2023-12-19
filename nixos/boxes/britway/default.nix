{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.britway) prefixes domain pubV4 assignedV6;
in
{
  nixos.systems.britway = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      vultr = {
        inherit domain;
        ipv4 = {
          address = pubV4;
          mask = 23;
          gateway = "45.76.140.1";
        };
        ipv6 = {
          iid = "::1";
          address = "2001:19f0:7402:128b::1";
        };
      };
      as211024 = {
        ipv4 = {
          address = net.cidr.host 5 prefixes.as211024.v4;
          gateway = null;
        };
        ipv6.address = net.cidr.host ((2*65536*65536*65536) + 1) prefixes.as211024.v6;
      };
    };

    configuration = { lib, pkgs, modulesPath, config, assignments, allAssignments, ... }:
      let
        inherit (lib) mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [
          "${modulesPath}/profiles/qemu-guest.nix"
          ./bgp.nix
        ];

        config = mkMerge [
          {
            boot = {
              initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "sr_mod" ];
              loader = {
                systemd-boot.enable = false;
                grub = {
                  enable = true;
                  device = "/dev/vda";
                };
              };
            };

            fileSystems = {
              "/boot" = {
                device = "/dev/disk/by-partuuid/c557ef12-da44-41d1-84f5-d32a711feefd";
                fsType = "ext4";
              };
              "/nix" = {
                device = "/dev/disk/by-partuuid/d42d0853-b054-4104-8afd-6d36287c7ca3";
                fsType = "ext4";
              };
              "/persist" = {
                device = "/dev/disk/by-partuuid/f14fbcf4-5242-456b-a4db-ef15d053d62e";
                fsType = "ext4";
                neededForBoot = true;
              };
            };

            services = {
              iperf3 = {
                enable = true;
                openFirewall = true;
              };
            };

            networking = { inherit domain; };

            systemd.network = {
              links = {
                "10-veth0" = {
                  matchConfig.PermanentMACAddress = "56:00:04:ac:6e:06";
                  linkConfig.Name = "veth0";
                };
              };

              networks = {
                "20-veth0" = mkMerge [
                  (networkdAssignment "veth0" assignments.vultr)
                  {
                    address = [ assignedV6 ];
                  }
                ];
                "90-l2mesh-as211024" = mkMerge [
                  (networkdAssignment "as211024" assignments.as211024)
                  {
                    matchConfig.Name = "as211024";
                    networkConfig.IPv6AcceptRA = mkForce false;
                  }
                ];
              };
            };

            my = {
              server.enable = true;
              secrets = {
                key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAmXC9egI46Qtaiifhq2I+rv2s1yPyzTlO4BHzUb+3Su";
                files = {
                  "l2mesh/as211024.key" = {};
                };
              };
              vpns = {
                l2.pskFiles = {
                  as211024 = config.age.secrets."l2mesh/as211024.key".path;
                };
              };

              firewall = { };
            };
          }
        ];
      };
  };
}
