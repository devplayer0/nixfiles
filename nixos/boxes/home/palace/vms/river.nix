{
  imports = [ (import ../../routing-common 0) ];

  config.nixos.systems.river = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    configuration = { lib, modulesPath, pkgs, config, assignments, allAssignments, ... }:
    let
      inherit (builtins) elemAt;
      inherit (lib) mkForce mkMerge;
      inherit (lib.my) net networkdAssignment mkVLAN;
      inherit (lib.my.c) networkd;
      inherit (lib.my.c.home) vlans domain prefixes roceBootModules routersPubV4;

      # river reaches the ONT over its 100G `lan` uplink to the dave switch (which downlinks to
      # brian, where the ONT lands). Digiweb delivers the ISP VLAN (pon-isp, 10) single-tagged at
      # the ONT alongside the ONT's untagged management traffic. With a single ONT there's no VLAN
      # collision, so the switches simply trunk the ISP's VLAN 10 straight through to river (PPPoE
      # runs directly on it) and PVID the ONT's untagged management port onto wan-pon-ont (140).
      # river takes .100 in the ONT's /24 (matching stream's modem-mgmt .100) to reach its web
      # UI at 192.168.100.1. (See docs/sites/home/switches.md for the switch side and the multi-ONT plan.)
      ontV4 = net.cidr.host 100 prefixes.ont.v4;

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
                plugin pppoe.so wan-pon-isp
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

        # PPPoE WAN (Digiweb): pppd owns the `wan` interface on top of wan-pon-isp (the switch's
        # swap of the ISP's VLAN 10), and its ip-up/ip-down hooks toggle the shared
        # wan-online.target. Nothing else Wants the target, so it stays inactive until the link
        # is actually up.
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

        # networkd's wait-online knows nothing about the pppd-owned `wan` interface, so
        # network-online.target is reached long before there's a route off-site. Gate the
        # installer fetch on the WAN instead, and retry it whenever the link returns.
        systemd.services.netboot-update = {
          after = [ "wan-online.target" ];
          wantedBy = mkForce [ "wan-online.target" ];
          partOf = [ "wan-online.target" ];
        };

        systemd.network = {
          netdevs = mkMerge [
            (mkVLAN "wan-pon-ont" vlans.wan-pon-ont)
            # The ISP VLAN is trunked through untranslated, so this is the raw pon-isp (10)
            (mkVLAN "wan-pon-isp" vlans.pon-isp)
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
              # both WAN VLANs arrive single-tagged on the 100G uplink to dave: wan-pon-ont (140,
              # the ONT's management, PVID-tagged at the brian edge) and the ISP's VLAN 10, trunked
              # straight through
              vlan = [ "wan-pon-ont" "wan-pon-isp" ];
            };
            # So we don't drop the IP we use to connect to NVMe-oF!
            "60-lan-hi".networkConfig.KeepConfiguration = "static";

            # ONT management: the brian edge PVIDs the ONT's untagged port onto wan-pon-ont, so give
            # ourselves an address in its /24 to reach the ONT's web UI at 192.168.100.1.
            "70-wan-pon-ont" = {
              matchConfig.Name = "wan-pon-ont";
              address = [ "${ontV4}/24" ];
              linkConfig = {
                RequiredForOnline = "no";
                MTUBytes = "1500";
              };
            };
            # pppd attaches PPPoE to this; just needs to be up with no L3. This is the ISP's
            # VLAN 10 trunked straight through from the ONT (no switch translation; see "55-lan").
            "71-wan-pon-isp" = {
              matchConfig.Name = "wan-pon-isp";
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
