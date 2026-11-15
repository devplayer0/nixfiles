{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.home) domain prefixes vips vlanDns hiMTU roceBootModules;
in
{
  imports = [ ./containers ];

  config.nixos.systems.sfh = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    assignments = {
      hi = {
        inherit domain;
        mtu = hiMTU;
        ipv4 = {
          address = net.cidr.host 81 prefixes.hi.v4;
          mask = 22;
          gateway = vips.hi.v4;
        };
        ipv6 = {
          iid = "::4:2";
          address = net.cidr.host (65536*4+2) prefixes.hi.v6;
        };
      };
    };

    configuration = { lib, modulesPath, pkgs, config, assignments, allAssignments, ... }:
    let
      inherit (lib) mapAttrs mkMerge mkForce;
      inherit (lib.my) networkdAssignment;
      inherit (lib.my.c) networkd;
      inherit (lib.my.c.home) domain;
    in
    {
      imports = [
        "${modulesPath}/profiles/qemu-guest.nix"
      ];

      config = {
        boot = {
          kernelModules = [ "kvm-amd" ];
          kernelParams = [ "console=ttyS0,115200n8" ];
          initrd = {
            availableKernelModules = [
              "virtio_pci" "ahci" "sr_mod" "virtio_blk"
            ] ++ roceBootModules;
            kernelModules = [ "dm-snapshot" ];
            systemd = {
              network = {
                networks = {
                  "20-lan-hi" = networkdAssignment "lan-hi" assignments.hi;
                };
              };
            };
          };
        };

        hardware = {
          enableRedistributableFirmware = true;
        };

        fileSystems = {
          "/nix" = {
            device = "/dev/main/nix";
            fsType = "ext4";
          };
          "/persist" = {
            device = "/dev/main/persist";
            fsType = "ext4";
            neededForBoot = true;
          };
          "/mnt/frigate" = {
            device = "/dev/disk/by-label/frigate";
            fsType = "ext4";
          };
        };

        networking = { inherit domain; };

        services = {
          lvm = {
            boot.thin.enable = true;
            dmeventd.enable = true;
          };
        };

        environment = {
          systemPackages = with pkgs; [
            usbutils
          ];
        };

        systemd.network = {
          links = {
            "10-lan-hi" = {
              matchConfig = {
                Driver = "mlx5_core";
                PermanentMACAddress = "52:54:00:ac:15:a9";
              };
              linkConfig = {
                Name = "lan-hi";
                MTUBytes = toString lib.my.c.home.hiMTU;
              };
            };
            "10-ctrs-hi" = {
              matchConfig = {
                Driver = "mlx5_core";
                PermanentMACAddress = "52:54:00:90:34:95";
              };
              linkConfig = {
                Name = "ctrs-hi";
                MTUBytes = toString lib.my.c.home.hiMTU;
              };
            };
            "10-ctrs-core" = {
              matchConfig = {
                Driver = "virtio_net";
                PermanentMACAddress = "52:54:00:72:67:51";
              };
              linkConfig.Name = "ctrs-core";
            };
            "10-ctrs-lo" = {
              matchConfig = {
                Driver = "virtio_net";
                PermanentMACAddress = "52:54:00:a5:7e:93";
              };
              linkConfig.Name = "ctrs-lo";
            };
          };

          networks = {
            "30-lan-hi" = mkMerge [
              (networkdAssignment "lan-hi" assignments.hi)
              {
                # So we don't drop the IP we use to connect to NVMe-oF!
                networkConfig = vlanDns "hi" // { KeepConfiguration = "static"; };
              }
            ];
            "30-ctrs-hi" = {
              matchConfig.Name = "ctrs-hi";
              linkConfig.RequiredForOnline = "no";
              networkConfig = networkd.noL3;
            };
            "30-ctrs-core" = {
              matchConfig.Name = "ctrs-core";
              linkConfig.RequiredForOnline = "no";
              networkConfig = networkd.noL3;
            };
            "30-ctrs-lo" = {
              matchConfig.Name = "ctrs-lo";
              linkConfig.RequiredForOnline = "no";
              networkConfig = networkd.noL3;
            };
          };
        };

        systemd.nspawn = {
          hass = {
            networkConfig = {
              MACVLAN = mkForce "ctrs-hi:host0 ctrs-lo:lan-lo";
            };
          };
          unifi = {
            networkConfig = {
              MACVLAN = mkForce "ctrs-hi:host0 ctrs-core:lan-core";
            };
          };
          # nspawn's default `/tmp` is 10% of RAM; agents need more scratch space
          slop-cannon = {
            filesConfig.TemporaryFileSystem = [ "/tmp:mode=1777,size=32G" ];
          };
        };

        systemd.services = {
          "systemd-nspawn@hass".serviceConfig.DeviceAllow = [
            "char-ttyUSB rw"
            "char-video4linux rw"
          ];
          # Coding agents; keep the other containers responsive
          "systemd-nspawn@slop-cannon".serviceConfig = {
            CPUWeight = 20;
            MemoryMax = "64G";
          };
        };

        my = {
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAaav5Se1E/AbqEXmADryVszYfNDscyP6jrWioN57R7";
          };
          server.enable = true;

          netboot.client = {
            enable = true;
          };
          nvme = {
            uuid = "85d7df36-0de0-431b-b06e-51f7c0a455b4";
            boot = {
              nqn = "nqn.2016-06.io.spdk:sfh";
              address = "192.168.68.80";
            };
          };

          containers.instances =
          let
            instances = {
              unifi = {};
              slop-cannon = {};
              hass = {
                bindMounts = {
                  "/mnt/frigate" = {
                    mountPoint = "/var/lib/frigate";
                    readOnly = false;
                  };
                  "/dev/bus/usb/001/002".readOnly = false;
                  "/dev/video0".readOnly = false;
                  "/dev/serial/by-id/usb-Nabu_Casa_Home_Assistant_Connect_ZBT-1_ce549704fe38ef11a2c2e5d154516304-if00-port0" = {
                    readOnly = false;
                    mountPoint = "/dev/ttyUSB0";
                  };
                };
              };
            };
          in
          mkMerge [
            instances
            (mapAttrs (n: i: {
              networking.macVLAN = "ctrs-hi";
            }) instances)
          ];
        };
      };
    };
  };
}
