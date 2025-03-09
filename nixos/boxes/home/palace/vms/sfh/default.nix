{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.home) domain prefixes vips hiMTU roceBootModules;
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
      inherit (lib) mapAttrs mkMerge;
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
            "10-lan-hi-ctrs" = {
              matchConfig = {
                Driver = "mlx5_core";
                PermanentMACAddress = "52:54:00:90:34:95";
              };
              linkConfig = {
                Name = "lan-hi-ctrs";
                MTUBytes = toString lib.my.c.home.hiMTU;
              };
            };
          };

          networks = {
            "30-lan-hi" = mkMerge [
              (networkdAssignment "lan-hi" assignments.hi)
              # So we don't drop the IP we use to connect to NVMe-oF!
              { networkConfig.KeepConfiguration = "static"; }
            ];
            "30-lan-hi-ctrs" = {
              matchConfig.Name = "lan-hi-ctrs";
              linkConfig.RequiredForOnline = "no";
              networkConfig = networkd.noL3;
            };
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
              # unifi = {};
              hass = {
                bindMounts = {
                  "/dev/bus/usb/001/002".readOnly = false;
                };
              };
            };
          in
          mkMerge [
            instances
            (mapAttrs (n: i: {
              networking.macVLAN = "lan-hi-ctrs";
            }) instances)
          ];
        };
      };
    };
  };
}
