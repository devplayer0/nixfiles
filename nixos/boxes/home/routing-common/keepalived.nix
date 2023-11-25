index: { lib, pkgs, ... }:
let
  inherit (builtins) attrNames;
  inherit (lib.my) net;
  inherit (lib.my.c.home) prefixes vips;

  vrrpIPs = family: map (vlan: {
    addr = "${vips.${vlan}.${family}}/${toString (net.cidr.length prefixes.${vlan}.${family})}";
    dev = "lan-${vlan}";
  }) (attrNames vips);
  mkVRRP = family: routerId: {
    state = if index == 0 then "MASTER" else "BACKUP";
    interface = "lan-core";
    priority = 255 - index;
    virtualRouterId = routerId;
    virtualIps = vrrpIPs family;
  };
in
{
  services = {
    keepalived = {
      enable = true;
      extraGlobalDefs = ''
        vrrp_version 3
        nftables keepalived
      '';
      vrrpInstances = {
        v4 = mkVRRP "v4" 51;
        v6 = mkVRRP "v6" 52;
      };
      extraConfig = ''
        vrrp_sync_group main {
          group {
            v4
            v6
          }
        }
      '';
    };
  };
}
