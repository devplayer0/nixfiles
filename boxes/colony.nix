{ lib, pkgs, inputs, ... }:
{
  fileSystems = {
    "/persist" = {
      device = "/dev/disk/by-label/persist";
      fsType = "ext4";
      neededForBoot = true;
    };
  };

  networking = { };

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
  };
}
