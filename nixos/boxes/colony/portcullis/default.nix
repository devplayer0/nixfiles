{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.colony) domain;
  home = lib.my.c.home;
in
{
  nixos.systems.portcullis = {
    system = "x86_64-linux";
    nixpkgs = "mine-stable";
    home-manager = "mine-stable";

    assignments = {
      # Staging-only: the 10G link lands on the home hi VLAN until portcullis is racked.
      hi = {
        domain = home.domain;
        mtu = home.hiMTU;
        ipv4 = {
          address = net.cidr.host 41 home.prefixes.hi.v4;
          mask = 22;
          gateway = home.vips.hi.v4;
        };
        ipv6 = {
          iid = "::6:1";
          address = net.cidr.host (65536*6+1) home.prefixes.hi.v6;
        };
      };
    };

    configuration = { lib, pkgs, config, assignments, ... }:
      let
        inherit (lib) mkMerge;
        inherit (lib.my) mkVLAN networkdAssignment;
        inherit (lib.my.c) networkd;
      in
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
          # Only some ports are patched in while the box is being staged, so don't block
          # boot on the others coming up.
          wait-online.anyInterface = true;

          netdevs = mkVLAN "lan-hi" home.vlans.hi;

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
            # racked at Nikhef. Until then it is staged at home, so every 2.5G port takes DHCP on
            # the lo VLAN and whichever one is patched in provides connectivity. kea registers
            # the DHCP hostname, making the box reachable as `portcullis.dyn.h.nul.ie`.
            "80-bootstrap" = {
              matchConfig.Name = "et2g5-*";
              DHCP = "yes";
              networkConfig.IPv6PrivacyExtensions = "no";
              linkConfig.RequiredForOnline = "routable";
            };

            # 10G up to jim's spare SFP+ port via an intermediary switch. That uplink is
            # untagged VLAN 1, so hi has to be tagged on its own interface.
            "81-et10g-0" = {
              matchConfig.Name = "et10g-0";
              vlan = [ "lan-hi" ];
              networkConfig = networkd.noL3;
              linkConfig = {
                # The carrier has to allow hi's jumbo frames before lan-hi can take that MTU
                MTUBytes = toString home.hiMTU;
                RequiredForOnline = "no";
              };
            };
            "82-lan-hi" = mkMerge [
              (networkdAssignment "lan-hi" assignments.hi)
              { networkConfig = home.vlanDns "hi"; }
            ];
          };
        };

        my = {
          # As above: no colony assignment yet, so deploy over the staging hi address.
          deploy.node.hostname = assignments.hi.ipv4.address;

          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAUolR93Byg+Daw8pUYHVpQ34ioxSc2C8vzj9F4KbqMs";
          };

          server.enable = true;
        };
      };
  };
}
