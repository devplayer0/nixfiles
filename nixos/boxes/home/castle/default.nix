{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c) networkd;
  inherit (lib.my.c.home) domain vlans prefixes vips roceBootModules;
in
{
  nixos.systems.castle = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    assignments = {
      hi = {
        inherit domain;
        ipv4 = {
          address = net.cidr.host 40 prefixes.hi.v4;
          mask = 22;
          gateway = vips.hi.v4;
        };
        ipv6 = {
          iid = "::3:1";
          address = net.cidr.host (65536*3+1) prefixes.hi.v6;
        };
      };
    };

    configuration = { lib, pkgs, modulesPath, config, systems, assignments, allAssignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) mkVLAN networkdAssignment;
      in
      {
        hardware = {
          enableRedistributableFirmware = true;
          cpu = {
            amd.updateMicrocode = true;
          };
          opengl.extraPackages = with pkgs; [
            intel-media-driver
          ];
          bluetooth.enable = true;
        };

        boot = {
          loader = {
            efi.canTouchEfiVariables = false;
            timeout = 10;
          };
          kernelPackages = lib.my.c.kernel.latest pkgs;
          kernelModules = [ "kvm-amd" "dm-snapshot" ];
          kernelParams = [ "amd_iommu=on" "amd_pstate=passive" ];
          kernelPatches = [
            # {
            #   # https://gitlab.freedesktop.org/drm/amd/-/issues/2354
            #   name = "drm-amd-display-fix-flickering-caused-by-S-G-mode";
            #   patch = ./0001-drm-amd-display-fix-flickering-caused-by-S-G-mode.patch;
            # }
          ];
          initrd = {
            availableKernelModules = [
              "thunderbolt" "xhci_pci" "nvme" "ahci" "usbhid" "usb_storage" "sd_mod"
              "8021q"
            ] ++ roceBootModules;
            systemd.network = {
              netdevs = mkVLAN "lan-hi" vlans.hi;
              networks = {
                "10-et100g" = {
                  matchConfig.Name = "et100g";
                  vlan = [ "lan-hi" ];
                  linkConfig.RequiredForOnline = "no";
                  networkConfig = networkd.noL3;
                };
                "20-lan-hi" = networkdAssignment "lan-hi" assignments.hi;
              };
            };
          };

          binfmt.emulatedSystems = [ "aarch64-linux" "armv7l-linux" ];
        };

        fileSystems = {
          "/nix" = {
            device = "/dev/nvmeof/nix";
            fsType = "ext4";
          };
          "/persist" = {
            device = "/dev/nvmeof/persist";
            fsType = "ext4";
            neededForBoot = true;
          };

          "/home" = {
            device = "/dev/nvmeof/home";
            fsType = "ext4";
          };
        };

        security = { };

        services = {
          hardware = {
            bolt.enable = true;
          };

          lvm = {
            boot.thin.enable = true;
            dmeventd.enable = true;
          };
          fstrim.enable = true;

          resolved = {
            enable = true;
            extraConfig = mkForce "";
            dnssec = "false";
          };

          pipewire.extraConfig.pipewire = {
            "10-buffer"."context.properties" = {
              "default.clock.quantum" = 128;
              "default.clock.max-quantum" = 128;
            };
          };
          blueman.enable = true;
        };

        programs = {
          virt-manager.enable = true;
          wireshark = {
            enable = true;
            package = pkgs.wireshark-qt;
          };
        };
        virtualisation.libvirtd.enable = true;

        networking = {
          inherit domain;
          firewall.enable = false;
        };

        environment.systemPackages = with pkgs; [
          dhcpcd
          pciutils
          usbutils
          lm_sensors
          linuxPackages.cpupower
          cifs-utils
          rpiboot
          rdma-core
          mstflint
          qperf
          ethtool
        ];

        nix = {
          gc.automatic = false;
        };

        systemd = {
          network = {
            netdevs = mkMerge [
              (mkVLAN "lan-hi" vlans.hi)
            ];
            links = {
              "10-et2.5g" = {
                matchConfig.MACAddress = "c8:7f:54:6e:17:0f";
                linkConfig.Name = "et2.5g";
              };
              "11-et10g" = {
                matchConfig.MACAddress = "c8:7f:54:6e:15:af";
                linkConfig.Name = "et10g";
              };
              "12-et100g" = {
                matchConfig.PermanentMACAddress = "24:8a:07:a8:fe:3a";
                linkConfig = {
                  Name = "et100g";
                  MTUBytes = toString lib.my.c.home.hiMTU;
                };
              };
            };
            networks = {
              "30-et100g" = {
                matchConfig.Name = "et100g";
                vlan = [ "lan-hi" ];
                networkConfig.IPv6AcceptRA = false;
              };
              "40-lan-hi" = mkMerge [
                (networkdAssignment "lan-hi" assignments.hi)
                # So we don't drop the IP we use to connect to NVMe-oF!
                { networkConfig.KeepConfiguration = "static"; }
              ];
            };
          };
        };

        my = {
          tmproot.size = "24G";

          user = {
            config.extraGroups = [ "input" ];

            tmphome = false;
            homeConfig = {
              services = { };

              home = {
                packages = with pkgs; [
                  jacktrip
                  qpwgraph
                  boardie
                ];
              };

              services = {
                blueman-applet.enable = true;
              };

              wayland.windowManager.sway = {
                config = {
                  output = {
                    HDMI-A-1 = {
                      transform = "270";
                      position = "0 0";
                      bg = "${./his-team-player.jpg} fill";
                    };
                    DP-1 = {
                      mode = "2560x1440@170Hz";
                      subpixel = "bgr";
                      position = "1440 560";
                    };
                    DP-2.position = "4000 560";
                  };
                };
              };

              my = {
                gui = {
                  standalone = true;
                  manageGraphical = true;
                };
              };
            };
          };

          #deploy.generate.system.mode = "boot";
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMlVuTzKObeaUuPocCF41IO/8X+443lzUJLuCIclt2vr";
          };
          netboot.client = {
            enable = true;
          };
          nvme = {
            uuid = "2230b066-a674-4f45-a1dc-f7727b3a9e7b";
            boot = {
              nqn = "nqn.2016-06.io.spdk:castle";
              address = "192.168.68.80";
            };
          };

          firewall = {
            enable = false;
          };

          gui.enable = true;
        };
      };
  };
}
