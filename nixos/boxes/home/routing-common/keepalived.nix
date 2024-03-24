index: { lib, pkgs, config, ... }:
let
  inherit (builtins) attrNames concatMap;
  inherit (lib) optional;
  inherit (lib.my) net;
  inherit (lib.my.c.home) prefixes vips;

  pingScriptFor = ip: {
    script = "${pkgs.iputils}/bin/ping -qnc 1 ${ip}";
    interval = 1;
    timeout = 1;
    rise = 3;
    fall = 3;
  };

  vlanIface = vlan: if vlan == "as211024" then vlan else "lan-${vlan}";
  vrrpIPs = family: concatMap (vlan: (optional (family == "v6") {
      addr = "fe80::1/64";
      dev = vlanIface vlan;
    }) ++ [
    {
      addr = "${vips.${vlan}.${family}}/${toString (net.cidr.length prefixes.${vlan}.${family})}";
      dev = vlanIface vlan;
    }
  ]) (attrNames vips);
  mkVRRP = family: routerId: {
    state = if index == 0 then "MASTER" else "BACKUP";
    interface = "lan-core";
    priority = 255 - index;
    virtualRouterId = routerId;
    virtualIps = vrrpIPs family;
    trackScripts = [ "${family}Alive" ];
    extraConfig = ''
      notify_master "${config.systemd.package}/bin/systemctl start radvd.service" root
      notify_backup "${config.systemd.package}/bin/systemctl stop radvd.service" root
    '';
  };
in
{
  users = with lib.my.c.ids; {
    users.keepalived_script = {
      uid = uids.keepalived_script;
      isSystemUser = true;
      group = "keepalived_script";
    };
    groups.keepalived_script.gid = gids.keepalived_script;
  };

  services = {
    keepalived = {
      enable = true;
      enableScriptSecurity = true;
      extraGlobalDefs = ''
        vrrp_version 3
        nftables keepalived
      '';
      vrrpScripts = {
        v4Alive = pingScriptFor "1.1.1.1";
        v6Alive = pingScriptFor "2600::";
      };
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
