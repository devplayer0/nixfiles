{ lib, ... }: {
  nixos.systems.whale2 = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "whale-vm";
        altNames = [ "oci" ];
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.vms.v4}3";
        ipv6 = {
          iid = "::3";
          address = "${lib.my.colony.start.vms.v6}3";
        };
      };
      oci = {
        name = "whale-vm-oci";
        domain = lib.my.colony.domain;
        ipv4 = {
          address = "${lib.my.colony.start.oci.v4}1";
          gateway = null;
        };
        ipv6.address = "${lib.my.colony.start.oci.v6}1";
      };
    };

    configuration = { lib, pkgs, modulesPath, config, assignments, allAssignments, ... }:
      let
        inherit (builtins) mapAttrs toJSON;
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [
          "${modulesPath}/profiles/qemu-guest.nix"


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
              fstrim.enable = true;
              netdata.enable = true;
            };

            virtualisation = {
              podman = {
                enable = true;
              };
            };

            environment = {
              etc = {
                "cni/net.d/90-colony.conflist".text = toJSON {
                  cniVersion = "0.4.0";
                  name = "colony";
                  plugins = [
                    {
                      type = "bridge";
                      bridge = "oci";
                      isGateway = true;
                      ipMasq = false;
                      hairpinMode = true;
                      ipam = {
                        type = "host-local";
                        routes = [
                          { dst = "0.0.0.0/0"; }
                          { dst = "::/0"; }
                        ];
                        ranges = [
                          [
                            {
                              subnet = lib.my.colony.prefixes.oci.v4;
                              gateway = lib.my.colony.start.oci.v4 + "1";
                            }
                          ]
                          [
                            {
                              subnet = lib.my.colony.prefixes.oci.v6;
                              gateway = lib.my.colony.start.oci.v6 + "1";
                            }
                          ]
                        ];
                      };
                      capabilities.ips = true;
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
                "80-vms" = networkdAssignment "vms" assignments.internal;
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
