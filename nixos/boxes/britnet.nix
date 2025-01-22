{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.britnet) domain pubV4 prefixes;
in
{
  nixos.systems.britnet = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      allhost = {
        inherit domain;
        ipv4 = {
          address = pubV4;
          mask = 24;
          gateway = "77.74.199.1";
        };
        ipv6 = {
          address = "2a12:ab46:5344:99::a";
          gateway = "2a12:ab46:5344::1";
        };
      };
      vpn = {
        ipv4 = {
          address = net.cidr.host 1 prefixes.vpn.v4;
          gateway = null;
        };
        ipv6.address = net.cidr.host 1 prefixes.vpn.v6;
      };
    };

    configuration = { lib, pkgs, modulesPath, config, assignments, allAssignments, ... }:
      let
        inherit (lib) mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [
          "${modulesPath}/profiles/qemu-guest.nix"
        ];

        config = mkMerge [
          {
            boot = {
              initrd.availableKernelModules = [
                "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "ahci" "sr_mod" "virtio_blk"
              ];
              loader = {
                systemd-boot.enable = false;
                grub = {
                  enable = true;
                  device = "/dev/vda";
                };
              };
            };

            fileSystems = {
              "/boot" = {
                device = "/dev/disk/by-uuid/457444a1-81dd-4934-960c-650ad16c92b5";
                fsType = "ext4";
              };
              "/nix" = {
                device = "/dev/disk/by-uuid/992c0c79-5be6-45b6-bc30-dc82e3ec082a";
                fsType = "ext4";
              };
              "/persist" = {
                device = "/dev/disk/by-uuid/f020a955-54d5-4098-98ba-d3615781d96a";
                fsType = "ext4";
                neededForBoot = true;
              };
            };

            environment = {
              systemPackages = with pkgs; [
                wireguard-tools
              ];
            };

            services = {
              iperf3 = {
                enable = true;
                openFirewall = true;
              };

              tailscale = {
                enable = true;
                authKeyFile = config.age.secrets."tailscale-auth.key".path;
                openFirewall = true;
                interfaceName = "tailscale0";
                extraUpFlags = [
                  "--operator=${config.my.user.config.name}"
                  "--login-server=https://hs.nul.ie"
                  "--netfilter-mode=off"
                  "--advertise-exit-node"
                  "--accept-routes=false"
                ];
              };
            };

            networking = { inherit domain; };

            systemd.network = {
              netdevs = {
                "30-wg0" = {
                  netdevConfig = {
                    Name = "wg0";
                    Kind = "wireguard";
                  };
                  wireguardConfig = {
                    PrivateKeyFile = config.age.secrets."britnet/wg.key".path;
                    ListenPort = lib.my.c.britnet.vpn.port;
                  };
                  wireguardPeers = [
                    {
                      PublicKey = "EfPwREfZ/q3ogHXBIqFZh4k/1NRJRyq4gBkBXtegNkE=";
                      AllowedIPs = [
                        (net.cidr.host 10 prefixes.vpn.v4)
                        (net.cidr.host 10 prefixes.vpn.v6)
                      ];
                    }
                  ];
                };
              };

              links = {
                "10-veth0" = {
                  matchConfig.PermanentMACAddress = "00:db:d9:62:68:1a";
                  linkConfig.Name = "veth0";
                };
              };

              networks = {
                "20-veth0" = mkMerge [
                  (networkdAssignment "veth0" assignments.allhost)
                  {
                    dns = [ "1.1.1.1" "1.0.0.1" ];
                    routes = [
                      {
                        # Gateway is on a different network for some reason...
                        Destination = "2a12:ab46:5344::1";
                        Scope = "link";
                      }
                    ];
                  }
                ];
                "30-wg0" = mkMerge [
                  (networkdAssignment "wg0" assignments.vpn)
                  {
                    networkConfig.IPv6AcceptRA = mkForce false;
                  }
                ];
              };
            };

            my = {
              server.enable = true;
              secrets = {
                key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJIEx+1EC/lN6WKIaOB+O5LJgVHRK962YpZEPQg/m78O";
                files = {
                  "tailscale-auth.key" = {};
                  "britnet/wg.key" = {
                    owner = "systemd-network";
                  };
                };
              };

              firewall = {
                udp.allowed = [ lib.my.c.britnet.vpn.port ];
                trustedInterfaces = [ "tailscale0" ];
                extraRules = ''
                  table inet filter {
                    chain forward {
                      iifname wg0 oifname veth0 accept
                    }
                  }
                  table inet nat {
                    chain postrouting {
                      iifname { tailscale0, wg0 } oifname veth0 snat ip to ${assignments.allhost.ipv4.address}
                      iifname { tailscale0, wg0 } oifname veth0 snat ip6 to ${assignments.allhost.ipv6.address}
                    }
                  }
                '';
              };
            };
          }
        ];
      };
  };
}
