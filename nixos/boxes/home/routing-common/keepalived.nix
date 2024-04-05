index: { lib, pkgs, config, ... }:
let
  inherit (builtins) attrNames concatMap length;
  inherit (lib) optional concatMapStringsSep;
  inherit (lib.my) net;
  inherit (lib.my.c.home) prefixes vips;

  pingScriptFor = name: ips:
  let
    script' = pkgs.writeShellScript
      "keepalived-ping-${name}"
      (concatMapStringsSep " || " (ip: "${pkgs.iputils}/bin/ping -qnc 1 -W 1 ${ip}") ips);
  in
  {
    script = toString script';
    interval = 1;
    timeout = (length ips) + 1;
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
        v4Alive = pingScriptFor "v4" [ "1.1.1.1" "8.8.8.8" "216.218.236.2" ];
        v6Alive = pingScriptFor "v6" [ "2606:4700:4700::1111" "2001:4860:4860::8888" "2600::" ];
      };
      vrrpInstances = {
        v4 = mkVRRP "v4" 51;
        v6 = mkVRRP "v6" 52;
      };
      # Actually disable this for now, don't want to fault IPv4 just because IPv6 is broken...
      # extraConfig = ''
      #   vrrp_sync_group main {
      #     group {
      #       v4
      #       v6
      #     }
      #   }
      # '';
    };
  };
}
