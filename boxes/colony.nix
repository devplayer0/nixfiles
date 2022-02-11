{ lib, pkgs, inputs, ... }:
  {
    fileSystems = {
      "/persist" = {
        device = "/dev/disk/by-label/persist";
        fsType = "ext4";
        neededForBoot = true;
      };
    };

    my = {
      server.enable = true;
    };
  }
