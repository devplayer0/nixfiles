{
  nixos.systems.colony = {
    system = "x86_64-linux";
    nixpkgs = "stable";
    home-manager = "unstable";
    docCustom = false;

    configuration = { lib, pkgs, modulesPath, ... }:
      {
        imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

        my = {
          firewall = {
            trustedInterfaces = [ "blah" ];
            nat = {
              externalInterface = "eth0";
              forwardPorts = [
                {
                  proto = "tcp";
                  sourcePort = 2222;
                  destination = "127.0.0.1:22";
                }
              ];
            };
          };
          server.enable = true;
          tmproot.unsaved.ignore = [
            "/var/db/dhcpcd/enp1s0.lease"
          ];
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
        };

        networking = {
          interfaces.enp1s0.useDHCP = true;
        };
      };
  };
}
