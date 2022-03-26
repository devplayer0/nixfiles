{
  nixos.systems.colony = {
    system = "x86_64-linux";
    nixpkgs = "unstable";
    home-manager = "unstable";

    configuration = { lib, pkgs, modulesPath, config, ... }:
      let
        inherit (lib) mkIf;
      in
      {
        imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

        my = {
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkqdN5t3UKwrNOOPKlbnG1WYhnkV5H9luAzMotr8SbT";
            files."test.txt" = {};
          };

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

          containers = {
            instances.vaultwarden = {};
          };
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
          interfaces = mkIf (!config.my.build.isDevVM) {
            enp1s0.useDHCP = true;
          };
        };

        #systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
      };
  };
}
