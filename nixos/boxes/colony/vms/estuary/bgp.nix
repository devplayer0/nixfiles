{ lib, pkgs, config, assignments, allAssignments, ... }:
let
in
{
  config = {
    services = {
      bird2 = {
        enable = true;
        # TODO: Clean up and modularise
        config = ''
          define OWNAS = 211024;

          define OWNIP6 = 2a0e:97c0:4df:0:3::1;
          define OWNNET6 = 2a0e:97c0:4d0::/44;
          define OWNNETSET6 = [2a0e:97c0:4d0::/44+];
          #define TRANSSET6 = [::1/128];

          define INTNET6 = 2a0e:97c0:4df::/48;
          define AMSNET6 = 2a0e:97c0:4d2::/48;
          define HOMENET6 = 2a0e:97c0:4d0::/48;

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
          #protocol direct {
          #	interface "devplayer0";
          #	ipv6;
          #}
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

          protocol kernel {
            #learn;
            ipv6 {
              #import filter bgp_export;
              import none;
              export filter {
                if net ~ OWNNETSET6 then reject;
                krt_prefsrc = OWNIP6;
                accept;
              };
            };
          }

          template bgp base_bgp {
            local as OWNAS;
            direct;
            ipv6 {
              export filter bgp_export;
            };
          }

          template bgp upstream_bgp from base_bgp {
            ipv6 {
              import none;
            };
          }
          template bgp peer_bgp from base_bgp {
            ipv6 {
              import filter bgp_import;
            };
          }

          protocol bgp coloclue from upstream_bgp {
            description "ColoClue";
            neighbor 2a02:898:0:20::1 as 8283;
          }

          protocol bgp peer_luje from peer_bgp {
            description "LUJE.net";
            neighbor 2001:7f8:d9:5b::b93e:1 as 212855;
          }
        '';
      };
    };
  };
}
