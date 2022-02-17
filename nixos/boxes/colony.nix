{ lib, pkgs, ... }:
{
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

    homeConfig = {};
  };

  fileSystems = {
    "/persist" = {
      device = "/dev/disk/by-label/persist";
      fsType = "ext4";
      neededForBoot = true;
    };
  };

  networking = { };
}
