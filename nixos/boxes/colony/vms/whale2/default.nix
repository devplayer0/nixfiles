{ lib, ... }:
let
  inherit (builtins) mapAttrs;
  inherit (lib) mkForce;
in
{
  nixos.systems.whale2 = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      routing = {
        name = "whale-vm-routing";
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.vms.v4}3";
      };
      internal = {
        name = "whale-vm";
        altNames = [ "oci" ];
        domain = lib.my.colony.domain;
        ipv4 = {
          address = "${lib.my.colony.start.vip1}6";
          mask = 32;
          gateway = null;
          genPTR = false;
        };
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

    extraAssignments = mapAttrs (n: i: {
      internal = {
        name = n;
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.oci.v4}${toString i}";
        ipv6.address = "${lib.my.colony.start.oci.v6}${toString i}";
      };
    }) {
      valheim-oci = 2;
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
              oci-containers = {
                backend = "podman";
              };
              # NixOS has switched to using netavark, which is native to podman. It's currently missing an option to
              # disable iptables rules generation, which is very annoying.
              containers.containersConf.settings.network.network_backend = mkForce "cni";
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
