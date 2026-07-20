{
  imports = [ (import ../../routing-common 0) ];

  config.nixos.systems.river = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    configuration = { lib, modulesPath, pkgs, config, assignments, allAssignments, ... }:
    let
      inherit (builtins) elemAt;
      inherit (lib) mkForce mkMerge mkIf;
      inherit (lib.my) networkdAssignment mkVLAN;
      inherit (lib.my.c) networkd;
      inherit (lib.my.c.home) vlans domain prefixes roceBootModules routersPubV4;

      # Digiweb currently delivers the ISP VLAN (pon-isp, 10) single-tagged, so PPPoE runs on a
      # VLAN 10 sitting directly on the physical WAN link. Flip this to true to nest it back
      # inside the wan-pon (131) transport VLAN — double-stacking also needs QinQ (tag-stacking)
      # on the switch feeding the ONT, or the BRAS never answers PADI.
      wanStacked = false;

      # river is routing-common index 0; the Digiweb static IP we request via IPCP
      pubV4 = elemAt routersPubV4 0;
    in
    {
      imports = [
        "${modulesPath}/profiles/qemu-guest.nix"
      ];

      config = {
        boot = {
          kernelModules = [ "kvm-amd" ];
          kernelParams = [ "console=ttyS0,115200n8" ];
          initrd = {
            availableKernelModules = [
              "virtio_pci" "ahci" "sr_mod" "virtio_blk"
              "8021q"
            ] ++ roceBootModules;
            kernelModules = [ "dm-snapshot" ];
            systemd = {
              network = {
                # Don't need to put the link config here, they're copied from main config
                netdevs = mkVLAN "lan-hi" vlans.hi;
                networks = {
                  "20-lan" = {
                    matchConfig.Name = "lan";
                    vlan = [ "lan-hi" ];
                    linkConfig.RequiredForOnline = "no";
                    networkConfig = networkd.noL3;
                  };
                  "30-lan-hi" = networkdAssignment "lan-hi" assignments.hi;
                };
              };
            };
          };
        };

        hardware = {
          enableRedistributableFirmware = true;
        };

        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-partuuid/3ec6c49e-b485-40cb-8eff-315581ac6fe9";
            fsType = "vfat";
          };
          "/nix" = {
            device = "/dev/main/nix";
            fsType = "ext4";
          };
          "/persist" = {
            device = "/dev/main/persist";
            fsType = "ext4";
            neededForBoot = true;
          };
        };

        services = {
          lvm = {
            boot.thin.enable = true;
            dmeventd.enable = true;
          };
          fstrim.enable = true;

          # TODO: re-enable once scheduling is tested
          networkd-dispatcher.enable = mkForce false;

          pppd = {
            enable = true;
            peers.digiweb = {
              autostart = true;
              enable = true;
              # Password is shared across all Digiweb customers, so no need for a secret
              config = ''
                plugin pppoe.so wan-vlan-inner
                name "digiweb@nga.digiweb.ie"
                password "digiweb"
                # request our static IP as the local address in IPCP (local:remote, remote left open)
                ${pubV4}:
                # no usepeerdns: we ignore Digiweb's resolvers and use the local recursive resolver
                lcp-echo-interval 1
                lcp-echo-failure 4
                noauth
                persist
                maxfail 0
                holdoff 5
                mtu 1500
                mru 1500
                noaccomp
                default-asyncmap
                ifname wan
              '';
            };
          };
        };

        # PPPoE WAN (Digiweb): pppd owns the `wan` interface on top of VLAN 10, and its
        # ip-up/ip-down hooks toggle the shared wan-online.target. Nothing else Wants the
        # target, so it stays inactive until the link is actually up.
        systemd.targets.wan-online.unitConfig.DefaultDependencies = false;

        environment.etc = {
          ppp-up = {
            target = "ppp/ip-up";
            mode = "0755";
            text = ''
              #!${pkgs.runtimeShell}
              ${pkgs.iproute2}/bin/ip route add default dev wan scope link metric 100
              ${config.systemd.package}/bin/systemctl --no-block start wan-online.target
            '';
          };
          ppp-down = {
            target = "ppp/ip-down";
            mode = "0755";
            text = ''
              #!${pkgs.runtimeShell}
              ${config.systemd.package}/bin/systemctl --no-block stop wan-online.target
              ${pkgs.iproute2}/bin/ip route del default dev wan scope link metric 100
            '';
          };
        };

        systemd.network = {
          netdevs = mkMerge [
            (mkIf wanStacked (mkVLAN "wan-vlan-outer" vlans.wan-pon))
            (mkVLAN "wan-vlan-inner" vlans.pon-isp)
          ];

          links = {
            "10-wan-old" = {
              matchConfig = {
                # Matching against MAC address seems to break VLAN interfaces
                # (since they share the same MAC address)
                Driver = "virtio_net";
                PermanentMACAddress = "e0:d5:5e:68:0c:6e";
              };
              linkConfig = {
                Name = "wan-old";
                RxBufferSize = 4096;
                TxBufferSize = 4096;
              };
            };

            "10-lan" = {
              matchConfig = {
                Driver = "mlx5_core";
                PermanentMACAddress = "52:54:00:8a:8a:f2";
              };
              linkConfig = {
                Name = "lan";
                MTUBytes = toString lib.my.c.home.hiMTU;
              };
            };
          };

          networks = {
            "55-lan" = {
              # outer transport VLAN when stacked, otherwise the ISP VLAN directly on lan
              vlan = [ (if wanStacked then "wan-vlan-outer" else "wan-vlan-inner") ];
            };
            # So we don't drop the IP we use to connect to NVMe-oF!
            "60-lan-hi".networkConfig.KeepConfiguration = "static";

            "70-wan-vlan-outer" = mkIf wanStacked {
              matchConfig.Name = "wan-vlan-outer";
              vlan = [ "wan-vlan-inner" ];
              networkConfig = networkd.noL3;
              # baby jumbo: carries the inner VLAN's frames, whose 4B tag counts as payload
              # at this layer, so it needs 1512 (inner's 1508B payload + the inner 802.1Q tag)
              linkConfig.MTUBytes = "1512";
            };
            # pppd attaches PPPoE to this; just needs to be up with no L3. Hangs off
            # wan-vlan-outer when stacked, otherwise directly off lan (see "55-lan").
            "71-wan-vlan-inner" = {
              matchConfig.Name = "wan-vlan-inner";
              linkConfig = {
                RequiredForOnline = "no";
                # baby jumbo: PPPoE's 8B overhead leaves a clean 1500 on ppp
                MTUBytes = "1508";
              };
              networkConfig = networkd.noL3;
            };
          };
        };

        my = {
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP9uFa4z9WPuXRFVA+PClQSitQCSPckhKTxo1Hq585Oa";
          };
          server.enable = true;
          nvme = {
            uuid = "12b52d80-ccb6-418d-9b2e-2be34bff3cd9";
            boot = {
              nqn = "nqn.2016-06.io.spdk:river";
              address = "192.168.68.80";
            };
          };

          netboot.server = {
            enable = true;
            ip = assignments.lo.ipv4.address;
            host = "boot.${domain}";
            allowedPrefixes = with prefixes; [ hi.v4 hi.v6 lo.v4 lo.v6 ];
            instances = [ "sfh" "castle" ];
          };

          deploy.node.hostname = "192.168.68.1";
        };
      };
    };
  };
}
