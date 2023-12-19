{ lib, pkgs, config, assignments, ... }:
let
  inherit (lib.my.c.britway) assignedV6;

  securebitSpace = "2a0e:97c0:4d0::/44";
  intnet6 = "2a0e:97c0:4df::/48";
  amsnet6 = "2a0e:97c0:4d2::/48";
  homenet6 = "2a0e:97c0:4d0::/48";
in
{
  config = {
    my = {
      secrets.files."britway/bgp-password-vultr.conf" = {
        owner = "bird2";
        group = "bird2";
      };
    };

    environment.etc."bird/vultr-password.conf".source = config.age.secrets."britway/bgp-password-vultr.conf".path;

    systemd = {
      services.bird2.after = [ "systemd-networkd-wait-online@veth0.service" ];
      network = {
        config.networkConfig.ManageForeignRoutes = false;
      };
    };

    services = {
      bird2 = {
        enable = true;
        preCheckConfig = ''
          echo '"dummy"' > vultr-password.conf
        '';
        # TODO: Clean up and modularise
        config = ''
          define OWNAS = 211024;

          define OWNIP4 = ${assignments.vultr.ipv4.address};
          define OWNNETSET4 = [ ${assignments.vultr.ipv4.address}/32 ];

          define INTNET6 = ${intnet6};
          define AMSNET6 = ${amsnet6};
          define HOMENET6 = ${homenet6};

          define OWNIP6 = ${assignments.vultr.ipv6.address};
          define OWNNETSET6 = [ ${intnet6}, ${amsnet6}, ${homenet6} ];
          #define TRANSSET6 = [ ::1/128 ];

          define DUB1IP6 = ${lib.my.c.home.vips.as211024.v6};

          define PREFIXP = 110;
          define PREFPEER = 120;

          filter bgp_import {
            if net !~ OWNNETSET4 && net !~ OWNNETSET6 then accept; else reject;
          }
          filter bgp_export {
            if net ~ OWNNETSET4 || net ~ OWNNETSET6 then accept; else reject;
          }

          router id from "veth0";

          protocol device {}
          protocol direct {
            interface "veth0";
            ipv4;
            ipv6;
          }
          protocol static static4 {
            ipv4 {
              import all;
              export none;
            };
          }
          protocol static static6 {
            # Special case: We have to do the routing on behalf of this _internal_ next-hop
            route INTNET6 via "as211024";
            route HOMENET6 via DUB1IP6;

            ipv6 {
              import all;
              export none;
            };
          }

          protocol kernel kernel4 {
            ipv4 {
              import none;
              export none;
            };
          }
          protocol kernel kernel6 {
            ipv6 {
              import none;
              export none;
            };
          }

          protocol bgp bgptools {
            local as OWNAS;
            multihop;
            description "bgp.tools monitoring";
            neighbor 2a0c:2f07:9459::b11 as 212232;
            source address OWNIP6;
            ipv4 {
              import none;
              export all;
              add paths tx;
            };
            ipv6 {
              import none;
              export all;
              add paths tx;
            };
          }

          template bgp base_bgp4 {
            local as OWNAS;
            direct;
            allow local as;
            ipv4 {
              import keep filtered;
              export none;
            };
          }

          template bgp upstream_bgp4 from base_bgp4 {
            ipv4 {
              #import none;
              import filter bgp_import;
            };
          }
          template bgp peer_bgp4 from base_bgp4 {
            ipv4 {
              import filter bgp_import;
              preference PREFPEER;
            };
          }
          template bgp ixp_bgp4 from base_bgp4 {
            ipv4 {
              import filter bgp_import;
              preference PREFIXP;
            };
          }

          template bgp base_bgp6 {
            local ${assignedV6} as OWNAS;
            direct;
            # So we can see routes we announce from other routers
            allow local as;
            ipv6 {
              import keep filtered;
              export filter bgp_export;
            };
          }

          template bgp upstream_bgp6 from base_bgp6 {
            ipv6 {
              #import none;
              import filter bgp_import;
            };
          }
          template bgp peer_bgp6 from base_bgp6 {
            ipv6 {
              import filter bgp_import;
              preference PREFPEER;
            };
          }
          template bgp ixp_bgp6 from base_bgp6 {
            ipv6 {
              import filter bgp_import;
              preference PREFIXP;
            };
          }

          protocol bgp upstream4_vultr from upstream_bgp4 {
            description "Vultr transit (IPv4)";
            neighbor 169.254.169.254 as 64515;
            multihop 2;
            password
            include "vultr-password.conf";;
          }
          protocol bgp upstream6_vultr from upstream_bgp6 {
            description "Vultr transit (IPv6)";
            neighbor 2001:19f0:ffff::1 as 64515;
            multihop 2;
            password
            include "vultr-password.conf";;
          }
        '';
      };
    };
  };
}
