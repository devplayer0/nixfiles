{ lib, pkgs, config, assignments, allAssignments, ... }:
let
  securebitSpace = "2a0e:97c0:4d0::/44";
  intnet6 = "2a0e:97c0:4df::/48";
  amsnet6 = "2a0e:97c0:4d2::/48";
  homenet6 = "2a0e:97c0:4d0::/48";
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

          define INTNET6 = ${intnet6};
          define AMSNET6 = ${amsnet6};
          define HOMENET6 = ${homenet6};

          define OWNIP6 = ${assignments.base.ipv6.address};
          define OWNNETSET6 = [ ${intnet6}, ${amsnet6}, ${homenet6} ];
          #define TRANSSET6 = [ ::1/128 ];

          define DUB1IP6 = 2a0e:97c0:4df:0:2::1;

          define PREFIXP = 110;
          define PREFPEER = 120;

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
            interface "wan", "frys-ix", "nl-ix", "fogixp", "ifog-transit";
            ipv4;
            ipv6;
          }
          protocol static {
            # Special case: We have to do the routing on behalf of this _internal_ next-hop
            route INTNET6 via "as211024";
            route AMSNET6 via "base";
            route HOMENET6 via DUB1IP6;
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
                #krt_prefsrc = OWNIP4;
                accept;
              };
            };
          }
          protocol kernel kernel6 {
            ipv6 {
              import none;
              export filter {
                if net = HOMENET6 then accept;
                if net ~ OWNNETSET6 then reject;
                #krt_prefsrc = OWNIP6;
                accept;
              };
            };
          }

          protocol bgp bgptools {
            local as OWNAS;
            multihop;
            description "bgp.tools monitoring";
            neighbor 2a0c:2f07:9459::b10 as 212232;
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
            local as OWNAS;
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

          protocol bgp upstream6_ifog from upstream_bgp6 {
            description "iFog transit (IPv6)";
            neighbor 2a0c:9a40:100f:370::1 as 34927;
          }

          protocol bgp upstream6_frysix_he from upstream_bgp6 {
            description "Hurricane Electric (on Frys-IX, IPv6)";
            neighbor 2001:7f8:10f::1b1b:154 as 6939;
          }

          protocol bgp peer4_cc_luje from peer_bgp4 {
            description "LUJE.net (on ColoClue, IPv4)";
            neighbor 94.142.240.20 as 212855;
          }
          protocol bgp peer6_cc_luje from peer_bgp6 {
            description "LUJE.net (on ColoClue, IPv6)";
            neighbor 2a02:898:0:20::166:1 as 212855;
          }
          protocol bgp peer6_luje_labs from peer_bgp6 {
            description "LUJE.net labs (IPv6)";
            multihop 3;
            neighbor 2a07:cd40:1::9 as 202413;
          }

          protocol bgp ixp4_frysix_rs1 from ixp_bgp4 {
            description "Frys-IX route server 1 (IPv4)";
            neighbor 185.1.203.253 as 56393;
          }
          protocol bgp ixp6_frysix_rs1 from ixp_bgp6 {
            description "Frys-IX route server 1 (IPv6)";
            neighbor 2001:7f8:10f::dc49:253 as 56393;
          }

          protocol bgp ixp4_frysix_rs2 from ixp_bgp4 {
            description "Frys-IX route server 2 (IPv4)";
            neighbor 185.1.203.254 as 56393;
          }
          protocol bgp ixp6_frysix_rs2 from ixp_bgp6 {
            description "Frys-IX route server 2 (IPv6)";
            neighbor 2001:7f8:10f::dc49:254 as 56393;
          }

          protocol bgp peer4_frysix_luje from peer_bgp4 {
            description "LUJE.net (on Frys-IX, IPv4)";
            neighbor 185.1.203.152 as 212855;
          }
          protocol bgp peer6_frysix_luje from peer_bgp6 {
            description "LUJE.net (on Frys-IX, IPv6)";
            neighbor 2001:7f8:10f::3:3f95:152 as 212855;
          }
          protocol bgp peer4_frysix_he from peer_bgp4 {
            description "Hurricane Electric (on Frys-IX, IPv4)";
            neighbor 185.1.203.154 as 6939;
          }

          protocol bgp ixp4_nlix_rs1 from ixp_bgp4 {
            description "NL-ix route server 1 (IPv4)";
            neighbor 193.239.116.255 as 34307;
          }
          protocol bgp ixp6_nlix_rs1 from ixp_bgp6 {
            description "NL-ix route server 1 (IPv6)";
            neighbor 2001:7f8:13::a503:4307:1 as 34307;
          }

          protocol bgp ixp4_nlix_rs2 from ixp_bgp4 {
            description "NL-ix route server 2 (IPv4)";
            neighbor 193.239.117.0 as 34307;
          }
          protocol bgp ixp6_nlix_rs2 from ixp_bgp6 {
            description "NL-ix route server 2 (IPv6)";
            neighbor 2001:7f8:13::a503:4307:2 as 34307;
          }

          protocol bgp peer6_nlix_cloudflare1 from peer_bgp6 {
            description "Cloudflare NL-ix 1 (IPv6)";
            neighbor 2001:7f8:13::a501:3335:1 as 13335;
          }
          protocol bgp peer6_nlix_cloudflare2 from peer_bgp6 {
            description "Cloudflare NL-ix 2 (IPv6)";
            neighbor 2001:7f8:13::a501:3335:2 as 13335;
          }
          protocol bgp peer6_nlix_cloudflare3 from peer_bgp6 {
            description "Cloudflare NL-ix 3 (IPv6)";
            neighbor 2001:7f8:13::a501:3335:3 as 13335;
          }

          protocol bgp ixp4_fogixp_rs1 from ixp_bgp4 {
            description "FogIXP route server 1 (IPv4)";
            neighbor 185.1.147.111 as 47498;
          }
          protocol bgp ixp6_fogixp_rs1 from ixp_bgp6 {
            description "FogIXP route server 1 (IPv6)";
            neighbor 2001:7f8:ca:1::111 as 47498;
          }

          protocol bgp ixp4_fogixp_rs2 from ixp_bgp4 {
            description "FogIXP route server 2 (IPv4)";
            neighbor 185.1.147.222 as 47498;
          }
          protocol bgp ixp6_fogixp_rs2 from ixp_bgp6 {
            description "FogIXP route server 2 (IPv6)";
            neighbor 2001:7f8:ca:1::222 as 47498;
          }
        '';
      };
    };
  };
}
