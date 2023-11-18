{
  imports = [
    (import ./routing-common {
      index = 1;
      name = "oxbow";
    })
  ];

  config.nixos.systems.oxbow = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    configuration = { lib, pkgs, config, ... }:
    let
      inherit (lib);
    in
    {
      config = {
        boot = {
          kernelParams = [ "intel_iommu=on" ];
        };

        hardware = {
          enableRedistributableFirmware = true;
          cpu = {
            intel.updateMicrocode = true;
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

        my = {
          secrets = {
            # key = "ssh-ed25519 ";
          };
          server.enable = true;
        };
      };
    };
  };
}
