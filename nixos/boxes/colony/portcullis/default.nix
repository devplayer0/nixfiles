{ lib, ... }:
let
  inherit (lib.my.c.colony) domain;
in
{
  nixos.systems.portcullis = {
    system = "x86_64-linux";
    nixpkgs = "mine-stable";
    home-manager = "mine-stable";

    configuration = { lib, pkgs, config, ... }:
      {
        hardware = {
          enableRedistributableFirmware = true;
          cpu = {
            intel.updateMicrocode = true;
          };
        };

        boot = {
          kernelModules = [ "kvm-intel" ];
          kernelParams = [ "intel_iommu=on" ];
          initrd = {
            availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "usbhid" "sd_mod" "sr_mod" ];
            kernelModules = [ "dm-snapshot" ];
          };
        };

        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-uuid/1A70-EBCB";
            fsType = "vfat";
            options = [ "fmask=0022" "dmask=0022" ];
          };
          "/nix" = {
            device = "/dev/main/portcullis-nix";
            fsType = "ext4";
          };
          "/persist" = {
            device = "/dev/main/portcullis-persist";
            fsType = "ext4";
            neededForBoot = true;
          };
        };

        networking = { inherit domain; };

        environment.systemPackages = with pkgs; [
          pciutils
          usbutils
          ethtool
          lm_sensors
          smartmontools
        ];

        systemd.network = {
          # Only one port is patched in while the box is being staged, so don't block
          # boot on the others coming up.
          wait-online.anyInterface = true;

          links = {
            "10-et2g5-0" = {
              matchConfig.PermanentMACAddress = "00:d0:b4:05:ed:48";
              linkConfig.Name = "et2g5-0";
            };
            "10-et2g5-1" = {
              matchConfig.PermanentMACAddress = "00:d0:b4:05:ed:49";
              linkConfig.Name = "et2g5-1";
            };
            "10-et2g5-2" = {
              matchConfig.PermanentMACAddress = "00:d0:b4:05:ed:4a";
              linkConfig.Name = "et2g5-2";
            };
            "10-et2g5-3" = {
              matchConfig.PermanentMACAddress = "00:d0:b4:05:ed:4b";
              linkConfig.Name = "et2g5-3";
            };

            "11-et10g-0" = {
              matchConfig.PermanentMACAddress = "60:be:b4:2e:9b:a2";
              linkConfig.Name = "et10g-0";
            };
            "11-et10g-1" = {
              matchConfig.PermanentMACAddress = "60:be:b4:2e:9b:a3";
              linkConfig.Name = "et10g-1";
            };
          };

          networks = {
            # TODO: replace with the colony assignments and routing config once portcullis is
            # racked at Nikhef. Until then it is staged on the home lo VLAN, so every 2.5G port
            # takes DHCP and whichever one is patched in provides connectivity. kea registers
            # the DHCP hostname, making the box reachable as `portcullis.dyn.h.nul.ie`.
            "80-bootstrap" = {
              matchConfig.Name = "et2g5-*";
              DHCP = "yes";
              networkConfig.IPv6PrivacyExtensions = "no";
              linkConfig.RequiredForOnline = "routable";
            };
          };
        };

        my = {
          # As above: no colony assignment yet, so point deploy at the staging DHCP name.
          deploy.node.hostname = "portcullis.dyn.${lib.my.c.home.domain}";

          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAUolR93Byg+Daw8pUYHVpQ34ioxSc2C8vzj9F4KbqMs";
          };

          server.enable = true;
        };
      };
  };
}
