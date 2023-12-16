index: { lib, pkgs, config, ... }:
let
  inherit (builtins) attrNames concatMap;
  inherit (lib) optional;
  inherit (lib.my) net;
  inherit (lib.my.c.home) prefixes vips;

  vlanIface = vlan: if vlan == "as211024" then vlan else "lan-${vlan}";
  vrrpIPs = family: concatMap (vlan: [
    {
      addr = "${vips.${vlan}.${family}}/${toString (net.cidr.length prefixes.${vlan}.${family})}";
      dev = vlanIface vlan;
    }
  ] ++ (optional (family == "v6") {
    addr = "fe80::1/64";
    dev = vlanIface vlan;
  })) (attrNames vips);
  mkVRRP = family: routerId: {
    state = if index == 0 then "MASTER" else "BACKUP";
    interface = "lan-core";
    priority = 255 - index;
    virtualRouterId = routerId;
    virtualIps = vrrpIPs family;
    extraConfig = ''
      notify_master "${config.systemd.package}/bin/systemctl start radvd.service"
      notify_backup "${config.systemd.package}/bin/systemctl stop radvd.service"
    '';
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
