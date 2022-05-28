{ lib, pkgs, config, ... }:
let
  inherit (builtins) isList;
  inherit (lib) mkMerge mkIf mkDefault mapAttrsToList concatMapStringsSep concatStringsSep;
  inherit (lib.my) mkBoolOpt' mkOpt';

  # Yoinked from nixos/modules/services/networking/pdns-recursor.nix
  oneOrMore  = type: with lib.types; either type (listOf type);
  valueType  = with lib.types; oneOf [ int str bool path ];
  configType = with lib.types; attrsOf (nullOr (oneOrMore valueType));

  toBool    = val: if val then "yes" else "no";
  serialize = val: with lib.types;
         if str.check       val then val
    else if int.check       val then toString val
    else if path.check      val then toString val
    else if bool.check      val then toBool val
    else if isList          val then (concatMapStringsSep "," serialize val)
    else "";
  settingsToLines = s: concatStringsSep "\n" (mapAttrsToList (k: v: "${k}=${serialize v}") s);

  bindList = l: "{ ${concatStringsSep "; " l} }";
  bindAlsoNotify = with lib.types; mkOpt' (listOf str) [ ] "List of additional address to send DNS NOTIFY messages to.";
  bindZoneOpts = with lib.types; { name, config, ... }: {
    options = {
      type = mkOpt' (enum [ "master" "slave" "native" ]) "native" "Zone type.";
      masters = mkOpt' (listOf str) [ ] "List of masters to retrieve data from (as slave).";
      also-notify = bindAlsoNotify;

      template = mkBoolOpt' true "Whether to run the zone contents through a template for post-processing.";
      text = mkOpt' (nullOr lines) null "Inline content of the zone file.";
      path = mkOpt' path null "Path to zone file.";
    };

    config.path = mkIf (config.text != null) (pkgs.writeText "${name}.zone" config.text);
  };
  namedZone = n: o: ''
    zone "${n}" IN {
      file "/run/pdns/bind-zones/${n}.zone";
      type ${o.type};
      masters ${bindList o.masters};
      also-notify ${bindList o.also-notify};
    };
  '';

  loadZonesCommon = pkgs.writeShellScript "pdns-bind-load-common.sh" ''
    loadZones() {
      for z in /etc/pdns/bind-zones/*.zone; do
        zoneName="$(echo "$z" | ${pkgs.gnused}/bin/sed -rn 's|/etc/pdns/bind-zones/(.*)\.zone|\1|p')"

        zDat="/var/lib/pdns/bind-zones/"$zoneName".dat"
        newZonePath="$(readlink -f "$z")"
        if [ ! -e "$zDat" ]; then
          echo "zonePath=\"$newZonePath\"" > "$zDat"
          echo "serial=$(date +%Y%m%d00)" >> "$zDat"
        fi
        source "$zDat"

        subSerial() {
          ${pkgs.gnused}/bin/sed "s/@@SERIAL@@/$serial/g" < "$z" > /run/pdns/bind-zones/"$zoneName".zone
        }
        # Zone in /run won't have changed if it didn't exist
        if [ "$newZonePath" != "$zonePath" ]; then
          echo "$zoneName has changed; incrementing serial..."
          ((serial++))
          echo "zonePath=\"$newZonePath\"" > "$zDat"
          echo "serial=$serial" >> "$zDat"

          subSerial
          if [ "$1" = reload ]; then
            echo "Reloading $zoneName"
            ${pkgs.pdns}/bin/pdns_control bind-reload-now "$zoneName"
          fi
        elif [ "$1" != reload ]; then
          subSerial
        fi
      done
    }
  '';

  cfg = config.my.pdns;

  namedConf = pkgs.writeText "pdns-named.conf" ''
    options {
      directory "/run/pdns/bind-zones";
      also-notify ${bindList cfg.auth.bind.options.also-notify};
    };

    ${concatStringsSep "\n" (mapAttrsToList namedZone cfg.auth.bind.zones)}
  '';

  templateZone = n: s: pkgs.runCommand "${n}.zone" {
    passAsFile = [ "script" ];
    script = ''
      import re
      import ipaddress
      import sys

      def ptr(m):
        ip = ipaddress.ip_address(m.group(1))
        return '.'.join(ip.reverse_pointer.split('.')[:int(m.group(2))])
      ex = re.compile(r'@@PTR:(.+):(\d+)@@')

      for line in sys.stdin:
        print(ex.sub(ptr, line), end=''')
    '';
  } ''
    ${pkgs.python310}/bin/python "$scriptPath" < "${s}" > "$out"
  '';
  zones = pkgs.linkFarm "pdns-bind-zones" (mapAttrsToList (n: o: rec {
    name = "${n}.zone";
    path = if o.template then templateZone n o.path else o.path;
  }) cfg.auth.bind.zones);
in
{
  options.my.pdns = with lib.types; {
    auth = {
      enable = mkBoolOpt' false "Whether to enable PowerDNS authoritative nameserver.";
      settings = mkOpt' configType { } "Authoritative server settings.";

      bind = {
        options = {
          also-notify = bindAlsoNotify;
        };
        zones = mkOpt' (attrsOf (submodule bindZoneOpts)) { } "BIND-style zones definitions.";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.auth.enable {
      my = {
        tmproot.persistence.config.directories = [ "/var/lib/pdns" ];
        pdns.auth.settings = {
          launch = [ "bind" ];
          socket-dir = "/run/pdns";
          bind-config = namedConf;
          expand-alias = mkDefault true;
        };
      };

      environment = {
        # For pdns_control etc
        systemPackages = with pkgs; [
          pdns
        ];

        etc."pdns/bind-zones".source = "${zones}/*";
      };

      systemd.services.pdns = {
        preStart = ''
          source ${loadZonesCommon}

          mkdir /run/pdns/bind-zones
          mkdir -p /var/lib/pdns/bind-zones
          loadZones start
        '';

        # pdns reloads existing zones, so the only trigger will be if the zone files themselves change. If any new zones
        # are added or removed, named.conf will change, in turn changing the overall pdns settings and causing pdns to
        # get fully restarted
        reload = ''
          source ${loadZonesCommon}

          loadZones reload
        '';

        reloadTriggers = [ zones ];
        serviceConfig = {
          RuntimeDirectory = "pdns";
          StateDirectory = "pdns";
        };
      };

      services.powerdns = {
        enable = true;
        extraConfig = settingsToLines cfg.auth.settings;
      };
    })
  ];
}
