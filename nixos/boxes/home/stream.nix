{
  imports = [ (import ./routing-common 1) ];

  config.nixos.systems.stream = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    configuration = { lib, pkgs, config, ... }:
    let
      inherit (lib);
    in
    {
      imports = [ ./routing-common/mstpd.nix ];

      config = {
        boot = {
          kernelModules = [ "kvm-intel" ];
          kernelParams = [ "intel_iommu=on" ];
          initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" "sd_mod" "sdhci_pci" ];
        };

        hardware = {
          enableRedistributableFirmware = true;
          cpu = {
            intel.updateMicrocode = true;
          };
        };

        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-partuuid/fe081885-9157-46b5-be70-46ac6fcb4069";
            fsType = "vfat";
          };
          "/nix" = {
            device = "/dev/disk/by-partuuid/a195e55e-397f-440d-a190-59ffa63cdb3f";
            fsType = "ext4";
          };
          "/persist" = {
            device = "/dev/disk/by-partuuid/ad71fafd-2d26-49c8-b0cb-794a28e0beb7";
            fsType = "ext4";
            neededForBoot = true;
          };
        };

        services = {
          mjpg-streamer = {
            enable = false;
            inputPlugin = "input_uvc.so";
            outputPlugin = "output_http.so -w @www@ -n -p 5050";
          };
          octoprint = {
            enable = false;
            host = "::";
            extraConfig = {
              plugins = {
                classicwebcam = {
                  snapshot = "/webcam/?action=snapshot";
                  stream = "/webcam/?action=stream";
                  streamRatio = "4:3";
                };
              };
              serial = {
                port = "/dev/ttyACM0";
                baudrate = 115200;
              };
              temperature.profiles = [
                {
                  bed = 60;
                  extruder = 215;
                  name = "PLA";
                }
              ];
            };
          };
        };

        systemd.network = {
          netdevs = {
            "25-lan" = {
              netdevConfig = {
                Name = "lan";
                Kind = "bridge";
              };
              extraConfig = ''
                [Bridge]
                STP=true
              '';
            };
          };
          links = {
            "10-wan" = {
              matchConfig = {
                # Matching against MAC address seems to break VLAN interfaces
                # (since they share the same MAC address)
                Driver = "igc";
                PermanentMACAddress = "00:f0:cb:ee:ca:dd";
              };
              linkConfig = {
                Name = "wan";
                RxBufferSize = 4096;
                TxBufferSize = 4096;
              };
            };
            "10-lan-jim" = {
              matchConfig = {
                Driver = "igc";
                PermanentMACAddress = "00:f0:cb:ee:ca:de";
              };
              linkConfig = {
                Name = "lan-jim";
                MTUBytes = toString lib.my.c.home.hiMTU;
              };
            };
            "10-et2" = {
              matchConfig = {
                Driver = "igc";
                PermanentMACAddress = "00:f0:cb:ee:ca:df";
              };
              linkConfig.Name = "et2";
            };

            "10-lan-dave" = {
              matchConfig = {
                Driver = "mlx4_en";
                PermanentMACAddress = "00:02:c9:d5:b1:d6";
              };
              linkConfig = {
                Name = "lan-dave";
                MTUBytes = toString lib.my.c.home.hiMTU;
              };
            };
            "10-et5" = {
              matchConfig = {
                Driver = "mlx4_en";
                PermanentMACAddress = "00:02:c9:d5:b1:d7";
              };
              linkConfig.Name = "et5";
            };
          };
          networks = {
            "50-lan-jim" = {
              matchConfig.Name = "lan-jim";
              networkConfig.Bridge = "lan";
            };
            "50-lan-dave" = {
              matchConfig.Name = "lan-dave";
              networkConfig.Bridge = "lan";
            };
          };
        };

        my = {
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPYTB4zeAqotrEJ8M+AiGm/s9PFsWlAodz3hYSROGuDb";
          };
          server.enable = true;
          # deploy.node.hostname = "192.168.68.2";
        };
      };
    };
  };
}
