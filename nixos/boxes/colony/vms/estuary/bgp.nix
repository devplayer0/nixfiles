{ lib, pkgs, config, assignments, allAssignments, ... }:
let
  securebitSpace = "2a0e:97c0:4d0::/44";
  amsnet6 = "2a0e:97c0:4d2::/48";
in
{
  config = {
    services = {
      bird2 = {
        enable = true;
        # TODO: Clean up and modularise
        config = ''
          define OWNAS = 211024;
          define OWNIP4 = ${assignments.internal.ipv4.address};
          define OWNNETSET4 = [ ${assignments.internal.ipv4.address}/32 ];

          define INTNET6 = 2a0e:97c0:4df::/48;
          define AMSNET6 = ${amsnet6};
          define HOMENET6 = 2a0e:97c0:4d0::/48;

          define OWNIP6 = ${assignments.internal.ipv6.address};
          define OWNNETSET6 = [ ${amsnet6} ];
          #define TRANSSET6 = [ ::1/128 ];

          define DUB1IP6 = 2a0e:97c0:4df:0:2::1;

          #function should_export6() {
          #	return net ~ OWNNETSET6 || (transit && net ~ TRANSSET6);
          #}

          filter bgp_import {
            if net !~ OWNNETSET6 then accept; else reject;
          }
          filter bgp_export {
            if net ~ OWNNETSET6 then accept; else reject;
          }

          router id from "wan";

          protocol device {}
          protocol direct {
            interface "wan";
            ipv4;
            ipv6;
          }
          protocol static {
            # Special case: We have to do the routing on behalf of this _internal_ next-hop
            #route INTNET6 via "devplayer0";
            route AMSNET6 via "base";
            #route HOMENET6 via DUB1IP6;
            ipv6 {
              import all;
              export none;
            };
          }

          protocol kernel kernel4 {
            ipv4 {
              import none;
              export filter {
                if net ~ OWNNETSET4 then reject;
                krt_prefsrc = OWNIP4;
                accept;
              };
            };
          }
          protocol kernel kernel6 {
            ipv6 {
              import none;
              export filter {
                if net ~ OWNNETSET6 then reject;
                krt_prefsrc = OWNIP6;
                accept;
              };
            };
          }

          protocol bgp bgptools {
            local as OWNAS;
            multihop;
            description "bgp.tools monitoring";
            neighbor 2a0c:2f07:9459::b8 as 212232;
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
            };
          }

          template bgp base_bgp6 {
            local as OWNAS;
            direct;
            # So we can see routes we announce from other routers
            allow local as;
            ipv6 {
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
            };
          }

          protocol bgp upstream4_coloclue_eun2 from upstream_bgp4 {
            description "ColoClue euNetworks 2 (IPv4)";
            neighbor 94.142.240.253 as 8283;
          }
          protocol bgp upstream4_coloclue_eun3 from upstream_bgp4 {
            description "ColoClue euNetworks 3 (IPv4)";
            neighbor 94.142.240.252 as 8283;
          }

          protocol bgp upstream6_coloclue_eun2 from upstream_bgp6 {
            description "ColoClue euNetworks 2 (IPv6)";
            neighbor 2a02:898:0:20::e2 as 8283;
          }
          protocol bgp upstream6_coloclue_eun3 from upstream_bgp6 {
            description "ColoClue euNetworks 3 (IPv6)";
            neighbor 2a02:898:0:20::e1 as 8283;
          }

          protocol bgp peer4_luje from peer_bgp4 {
            description "LUJE.net (IPv4)";
            neighbor 94.142.240.20 as 212855;
          }
          protocol bgp peer6_luje from peer_bgp6 {
            description "LUJE.net (IPv6)";
            neighbor 2a02:898:0:20::166:1 as 212855;
          }
        '';
      };
    };
  };
}
