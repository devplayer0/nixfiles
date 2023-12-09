{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.colony) domain prefixes;
in
{
  nixos.systems.git = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      routing = {
        name = "git-vm-routing";
        inherit domain;
        ipv4.address = net.cidr.host 4 prefixes.vms.v4;
      };
      internal = {
        name = "git-vm";
        inherit domain;
        ipv4 = {
          address = net.cidr.host 0 prefixes.vip3;
          mask = 32;
          gateway = null;
          genPTR = false;
        };
        ipv6 = {
          iid = "::4";
          address = net.cidr.host 4 prefixes.vms.v6;
        };
      };
    };

    configuration = { lib, pkgs, modulesPath, config, assignments, allAssignments, ... }:
      let
        inherit (lib) mkMerge;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [
          "${modulesPath}/profiles/qemu-guest.nix"

          ./gitea.nix
          ./gitea-actions.nix
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
            };

            systemd.network = {
              links = {
                "10-vms" = {
                  matchConfig.MACAddress = "52:54:00:75:78:a8";
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
              secrets.key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP+KINpHLMduBuW96JzfSRDLUzkI+XaCBghu5/wHiW5R";
              server.enable = true;

              firewall = {
                tcp.allowed = [ 19999 ];
                trustedInterfaces = [ "oci" ];
              };
            };
          }
        ];
      };
  };
}
