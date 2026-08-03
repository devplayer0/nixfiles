{
  imports = [ (import ./routing-common 1) ];

  config.nixos.systems.stream = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    configuration = { lib, pkgs, config, ... }:
    let
      inherit (lib) mkMerge;
      inherit (lib.my) net;
      inherit (lib.my.c) networkd;
      inherit (lib.my.c.home) prefixes;

      # Static address on the Virgin Media modem's management subnet. Kept as a plain interface
      # address (not a network assignment) since it's local to this box's WAN uplink.
      modemV4 = net.cidr.host 100 prefixes.modem.v4;
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

        # wan carries a permanent static modem-management address (modemV4)
        # alongside the DHCP public IP, so wait-online@wan reports "online" as soon as
        # the static address is up - before the DHCP lease arrives. ipsec's left= is the
        # public IP, so gating on wait-online lets it start unoriented and never connect.
        # Gate instead on the DHCP default route, which only exists once the public lease
        # is up (the static modem address has no gateway).
        systemd.services.wan-wait-online = {
          description = "Wait for the wan default route (public DHCP lease)";
          after = [ "systemd-networkd.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "300";
          };
          script = ''
            until [ -n "$(${pkgs.iproute2}/bin/ip -4 route show default dev wan)" ]; do
              sleep 1
            done
          '';
        };
        systemd.targets.wan-online = {
          requires = [ "wan-wait-online.service" ];
          after = [ "wan-wait-online.service" ];
          wantedBy = [ "multi-user.target" ];
        };

        systemd.network = {
          netdevs = {
            "25-lan" = {
              netdevConfig = {
                Name = "lan";
                Kind = "bridge";
              };
              bridgeConfig.STP = true;
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
              bridgeConfig.Cost = 100;
            };
            "50-lan-dave" = {
              matchConfig.Name = "lan-dave";
              networkConfig.Bridge = "lan";
              bridgeConfig.Cost = 10;
            };

            "50-wan-ifb" = {
              matchConfig.Name = "wan-ifb";
              networkConfig = networkd.noL3;
              extraConfig = ''
                [CAKE]
                Bandwidth=490M
                RTTSec=50ms
                PriorityQueueingPreset=besteffort
                # DOCSIS preset
                OverheadBytes=18
                MPUBytes=64
                CompensationMode=none
              '';
            };
            "50-wan" = {
              matchConfig.Name = "wan";
              # Static modem-management address alongside the DHCP public lease. It has no
              # gateway, so the wan-wait-online gate keys off the DHCP default route instead.
              address = [ "${modemV4}/24" ];
              DHCP = "ipv4";
              dns = [ "127.0.0.1" "::1" ];
              dhcpV4Config.UseDNS = false;
              # IPv4-only WAN (public IPv6 arrives over the tunnel, not this link).
              networkConfig.IPv6AcceptRA = false;

              qdiscConfig = {
                Parent = "ingress";
                Handle = "0xffff";
              };
              extraConfig = ''
                [CAKE]
                Parent=root
                Bandwidth=48M
                RTTSec=50ms
              '';
            };
          };
        };

        my = {
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPYTB4zeAqotrEJ8M+AiGm/s9PFsWlAodz3hYSROGuDb";
          };
          server.enable = true;
          # The modem's management subnet shares the `wan` interface: skip its address when
          # picking our own wan A record, and reject untrusted clients from reaching it.
          homeRouter = {
            dns.wanSkipBroadcasts = [ (lib.my.netBroadcast prefixes.modem.v4) ];
            firewall.untrustedRejectV4 = [ prefixes.modem.v4 ];
          };
          # deploy.node.hostname = "192.168.68.2";
        };
      };
    };
  };
}
