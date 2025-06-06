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
      bird = {
        enable = true;
        package = pkgs.bird2;
        # TODO: Clean up and modularise
        config = ''
          define OWNAS = 211024;

          define CCVIP1 = ${lib.my.c.colony.prefixes.vip1};
          define CCVIP2 = ${lib.my.c.colony.prefixes.vip2};
          define CCVIP3 = ${lib.my.c.colony.prefixes.vip3};

          define OWNIP4 = ${assignments.internal.ipv4.address};
          define OWNNETSET4 = [ ${assignments.internal.ipv4.address}/32 ];
          define CCNETSET4 = [ ${lib.my.c.colony.prefixes.vip1}, ${lib.my.c.colony.prefixes.vip2}, ${lib.my.c.colony.prefixes.vip3} ];

          define INTNET6 = ${intnet6};
          define AMSNET6 = ${amsnet6};
          define HOMENET6 = ${homenet6};

          define OWNIP6 = ${assignments.base.ipv6.address};
          # we have issues with sending ICMPv6 too big back on the wrong interface right now...
          define OWNNETSET6 = [ ${intnet6}, ${amsnet6} ];
          define CCNETSET6 = [ ];
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
          filter bgp_export_cc {
            if net ~ OWNNETSET4 || net ~ OWNNETSET6 || net ~ CCNETSET4 || net ~ CCNETSET6 then accept; else reject;
          }

          router id from "wan";

          protocol device {}
          protocol direct {
            interface "wan", "frys-ix", "nl-ix", "fogixp", "ifog-transit";
            ipv4;
            ipv6;
          }
          protocol static static4 {
            route CCVIP1 via "base";
            route CCVIP2 via "base";
            route CCVIP3 via "base";

            ipv4 {
              import all;
              export none;
            };
          }
          protocol static static6 {
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
            ipv4 { export filter bgp_export_cc; };
          }
          protocol bgp upstream4_coloclue_eun3 from upstream_bgp4 {
            description "ColoClue euNetworks 3 (IPv4)";
            neighbor 94.142.240.252 as 8283;
            ipv4 { export filter bgp_export_cc; };
          }

          protocol bgp upstream6_coloclue_eun2 from upstream_bgp6 {
            description "ColoClue euNetworks 2 (IPv6)";
            neighbor 2a02:898:0:20::e2 as 8283;
            ipv6 { export filter bgp_export_cc; };
          }
          protocol bgp upstream6_coloclue_eun3 from upstream_bgp6 {
            description "ColoClue euNetworks 3 (IPv6)";
            neighbor 2a02:898:0:20::e1 as 8283;
            ipv6 { export filter bgp_export_cc; };
          }

          protocol bgp upstream6_ifog from upstream_bgp6 {
            description "iFog transit (IPv6)";
            neighbor 2a0c:9a40:100f:370::1 as 34927;
          }

          protocol bgp upstream6_frysix_he from upstream_bgp6 {
            description "Hurricane Electric (on Frys-IX, IPv6)";
            neighbor 2001:7f8:10f::1b1b:154 as 6939;
          }

          # Not working so well lately...
          # protocol bgp upstream4_fogixp_efero from upstream_bgp4 {
          #   description "efero transit (on FogIXP, IPv4)";
          #   neighbor 185.1.147.107 as 208431;
          # }
          # protocol bgp upstream6_fogixp_efero from upstream_bgp6 {
          #   description "efero transit (on FogIXP, IPv6)";
          #   neighbor 2001:7f8:ca:1::107 as 208431;
          # }

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

          protocol bgp ixp4_frysix_rs3 from ixp_bgp4 {
            description "Frys-IX route server 3 (IPv4)";
            neighbor 185.1.160.255 as 56393;
          }
          protocol bgp ixp6_frysix_rs3 from ixp_bgp6 {
            description "Frys-IX route server 3 (IPv6)";
            neighbor 2001:7f8:10f::dc49:1 as 56393;
          }

          protocol bgp ixp4_frysix_rs4 from ixp_bgp4 {
            description "Frys-IX route server 4 (IPv4)";
            neighbor 185.1.161.0 as 56393;
          }
          protocol bgp ixp6_frysix_rs4 from ixp_bgp6 {
            description "Frys-IX route server 4 (IPv6)";
            neighbor 2001:7f8:10f::dc49:2 as 56393;
          }

          protocol bgp peer4_frysix_luje from peer_bgp4 {
            description "LUJE.net (on Frys-IX, IPv4)";
            neighbor 185.1.160.152 as 212855;
          }
          protocol bgp peer6_frysix_luje from peer_bgp6 {
            description "LUJE.net (on Frys-IX, IPv6)";
            neighbor 2001:7f8:10f::3:3f95:152 as 212855;
          }

          protocol bgp peer4_frysix_he from peer_bgp4 {
            description "Hurricane Electric (on Frys-IX, IPv4)";
            neighbor 185.1.160.154 as 6939;
          }

          protocol bgp peer4_frysix_cloudflare1_old from peer_bgp4 {
            description "Cloudflare 1 (on Frys-IX, IPv4)";
            neighbor 185.1.203.217 as 13335;
          }
          protocol bgp peer4_frysix_cloudflare2_old from peer_bgp4 {
            description "Cloudflare 2 (on Frys-IX, IPv4)";
            neighbor 185.1.203.109 as 13335;
          }
          protocol bgp peer4_frysix_cloudflare1 from peer_bgp4 {
            description "Cloudflare 1 (on Frys-IX, IPv4)";
            neighbor 185.1.160.217 as 13335;
          }
          protocol bgp peer4_frysix_cloudflare2 from peer_bgp4 {
            description "Cloudflare 2 (on Frys-IX, IPv4)";
            neighbor 185.1.160.109 as 13335;
          }
          protocol bgp peer6_frysix_cloudflare1 from peer_bgp6 {
            description "Cloudflare 1 (on Frys-IX, IPv6)";
            neighbor 2001:7f8:10f::3417:217 as 13335;
          }
          protocol bgp peer6_frysix_cloudflare2 from peer_bgp6 {
            description "Cloudflare 2 (on Frys-IX, IPv6)";
            neighbor 2001:7f8:10f::3417:109 as 13335;
          }

          protocol bgp peer4_frysix_jurrian from peer_bgp4 {
            description "AS212635 aka jurrian (on Frys-IX, IPv4)";
            neighbor 185.1.160.134 as 212635;
          }
          protocol bgp peer6_frysix_jurrian from peer_bgp6 {
            description "AS212635 aka jurrian (on Frys-IX, IPv6)";
            neighbor 2001:7f8:10f::3:3e9b:134 as 212635;
          }

          protocol bgp peer4_frysix_meta1_old from peer_bgp4 {
            description "Meta 1 (on Frys-IX, IPv4)";
            neighbor 185.1.203.225 as 32934;
          }
          protocol bgp peer4_frysix_meta2_old from peer_bgp4 {
            description "Meta 2 (on Frys-IX, IPv4)";
            neighbor 185.1.203.226 as 32934;
          }
          protocol bgp peer4_frysix_meta1 from peer_bgp4 {
            description "Meta 1 (on Frys-IX, IPv4)";
            neighbor 185.1.160.225 as 32934;
          }
          protocol bgp peer4_frysix_meta2 from peer_bgp4 {
            description "Meta 2 (on Frys-IX, IPv4)";
            neighbor 185.1.160.226 as 32934;
          }
          protocol bgp peer6_frysix_meta1 from peer_bgp6 {
            description "Meta 1 (on Frys-IX, IPv6)";
            neighbor 2001:7f8:10f::80a6:225 as 32934;
          }
          protocol bgp peer6_frysix_meta2 from peer_bgp6 {
            description "Meta 2 (on Frys-IX, IPv6)";
            neighbor 2001:7f8:10f::80a6:226 as 32934;
          }

          protocol bgp ixp4_nlix_rs1 from ixp_bgp4 {
            description "NL-ix route server 1 (IPv4)";
            neighbor 193.239.116.255 as 34307;
            ipv4 { preference (PREFIXP-1); };
          }
          protocol bgp ixp6_nlix_rs1 from ixp_bgp6 {
            description "NL-ix route server 1 (IPv6)";
            neighbor 2001:7f8:13::a503:4307:1 as 34307;
            ipv6 { preference (PREFIXP-1); };
          }

          protocol bgp ixp4_nlix_rs2 from ixp_bgp4 {
            description "NL-ix route server 2 (IPv4)";
            neighbor 193.239.117.0 as 34307;
            ipv4 { preference (PREFIXP-1); };
          }
          protocol bgp ixp6_nlix_rs2 from ixp_bgp6 {
            description "NL-ix route server 2 (IPv6)";
            neighbor 2001:7f8:13::a503:4307:2 as 34307;
            ipv6 { preference (PREFIXP-1); };
          }

          # protocol bgp peer4_nlix_cloudflare1 from peer_bgp4 {
          #   description "Cloudflare NL-ix 1 (IPv4)";
          #   neighbor 193.239.117.14 as 13335;
          #   ipv4 { preference (PREFPEER-1); };
          # }
          # protocol bgp peer4_nlix_cloudflare2 from peer_bgp4 {
          #   description "Cloudflare NL-ix 2 (IPv4)";
          #   neighbor 193.239.117.114 as 13335;
          #   ipv4 { preference (PREFPEER-1); };
          # }
          # protocol bgp peer4_nlix_cloudflare3 from peer_bgp4 {
          #   description "Cloudflare NL-ix 3 (IPv4)";
          #   neighbor 193.239.118.138 as 13335;
          #   ipv4 { preference (PREFPEER-1); };
          # }
          # protocol bgp peer6_nlix_cloudflare1 from peer_bgp6 {
          #   description "Cloudflare NL-ix 1 (IPv6)";
          #   neighbor 2001:7f8:13::a501:3335:1 as 13335;
          #   ipv6 { preference (PREFPEER-1); };
          # }
          # protocol bgp peer6_nlix_cloudflare2 from peer_bgp6 {
          #   description "Cloudflare NL-ix 2 (IPv6)";
          #   neighbor 2001:7f8:13::a501:3335:2 as 13335;
          #   ipv6 { preference (PREFPEER-1); };
          # }
          # protocol bgp peer6_nlix_cloudflare3 from peer_bgp6 {
          #   description "Cloudflare NL-ix 3 (IPv6)";
          #   neighbor 2001:7f8:13::a501:3335:3 as 13335;
          #   ipv6 { preference (PREFPEER-1); };
          # }
          protocol bgp peer4_nlix_jurrian from peer_bgp4 {
            description "AS212635 aka jurrian (on NL-ix, IPv4)";
            neighbor 193.239.117.55 as 212635;
            ipv4 { preference (PREFPEER-1); };
          }
          protocol bgp peer6_nlix_jurrian from peer_bgp6 {
            description "AS212635 aka jurrian (on NL-ix, IPv6)";
            neighbor 2001:7f8:13::a521:2635:1 as 212635;
            ipv6 { preference (PREFPEER-1); };
          }
          protocol bgp peer4_nlix_apple from peer_bgp4 {
            description "Apple (on NL-ix, IPv4)";
            neighbor 193.239.117.113 as 714;
            ipv4 { preference (PREFPEER-1); };
          }
          protocol bgp peer6_nlix_apple from peer_bgp6 {
            description "Apple (on NL-ix, IPv6)";
            neighbor 2001:7f8:13::a500:714:2 as 714;
            ipv6 { preference (PREFPEER-1); };
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

          protocol bgp peer4_fogixp_jurrian from peer_bgp4 {
            description "AS212635 aka jurrian (on FogIXP, IPv4)";
            neighbor 185.1.147.34 as 212635;
          }
          protocol bgp peer6_fogixp_jurrian from peer_bgp6 {
            description "AS212635 aka jurrian (on FogIXP, IPv6)";
            neighbor 2001:7f8:ca:1::34 as 212635;
          }
          protocol bgp peer4_fogixp_luje from peer_bgp4 {
            description "LUJE.net (on FogIXP, IPv4)";
            neighbor 185.1.147.42 as 212855;
          }
          protocol bgp peer6_fogixp_luje from peer_bgp6 {
            description "LUJE.net (on FogIXP, IPv6)";
            neighbor 2001:7f8:ca:1::42 as 212855;
          }
        '';
      };
    };
  };
}
