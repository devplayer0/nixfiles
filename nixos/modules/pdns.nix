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
  settingsToLines = s: (concatStringsSep "\n" (mapAttrsToList (k: v: "${k}=${serialize v}") s)) + "\n";

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

  staticZonePath = "/etc/pdns-bind-zones";
  loadZonesCommon = pkgs.writeShellScript "pdns-bind-load-common.sh" ''
    loadZones() {
      for z in ${staticZonePath}/*.zone; do
        zoneName="$(echo "$z" | ${pkgs.gnused}/bin/sed -rn 's|${staticZonePath}/(.*)\.zone|\1|p')"

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

  pdns-file-record = pkgs.writeShellApplication {
    name = "pdns-file-record";
    runtimeInputs = with pkgs; [ gnused moreutils pdns ];
    text = ''
      die() {
        echo "$@" >&2
        exit 1
      }
      usage() {
        die "usage: $0 <zone> <add|del> <fqdn> [content]"
      }

      add() {
        if [ $# -lt 2 ]; then
          usage
        fi

        file="$dir"/"$1"txt
        shift
        echo "$@" >> "$file"
      }
      del() {
        if [ $# -lt 1 ]; then
          usage
        fi

        file="$dir"/"$1"txt
        if [ $# -eq 1 ]; then
          rm "$file"
        else
          shift
          sed -i "/^""$*""$/!{q1}; /^""$*""$/d" "$file"
          exit $?
        fi
      }

      dir=/run/pdns/file-records
      mkdir -p "$dir"

      if [ $# -lt 2 ]; then
        usage
      fi
      zone="$1"
      shift
      cmd="$1"
      shift

      case "$cmd" in
      add)
        add "$@";;
      del)
        del "$@";;
      *)
        usage;;
      esac

      # TODO: This feels pretty hacky?
      zDat=/var/lib/pdns/bind-zones/"$zone".dat
      # shellcheck disable=SC1090
      source "$zDat"
      ((serial++))

      # Use sponge instead of `sed -i` because that actually uses a temporary file and clobbers ownership...
      sed "s/^serial=.*$/serial=$serial/g" "$zDat" | sponge "$zDat"
      sed "s/@@SERIAL@@/$serial/g" < ${staticZonePath}/"$zone".zone > /run/pdns/bind-zones/"$zone".zone
      pdns_control bind-reload-now "$zone"
    '';
  };

  fileRecScript = pkgs.writeText "file-record.lua" ''
    local path = "/run/pdns/file-records/" .. string.lower(qname:toStringNoDot()) .. ".txt"
    if not os.execute("test -e " .. path) then
      return {}
    end

    local values = {}
    for line in io.lines(path) do
      table.insert(values, line)
    end
    return values
  '';

  cfg = config.my.pdns;

  extraSettingsOpt = with lib.types; mkOpt' (nullOr str) null "Path to extra settings (e.g. for secrets).";
  baseAuthSettings = pkgs.writeText "pdns.conf" (settingsToLines cfg.auth.settings);
  baseRecursorSettings = pkgs.writeText "pdns-recursor.conf" (settingsToLines config.services.pdns-recursor.settings);
  generateSettings = type: base: dst: if (cfg."${type}".extraSettingsFile != null) then ''
    oldUmask="$(umask)"
    umask 006
    cat "${base}" "${cfg."${type}".extraSettingsFile}" > "${dst}"
    umask "$oldUmask"
  '' else ''
    cp "${base}" "${dst}"
  '';

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
      ex_ptr = re.compile(r'@@PTR:(.+):(\d+)@@')

      fr = '"dofile(\'${fileRecScript}\')"'
      ex_fr = re.compile(r'@@FILE@@')

      for line in sys.stdin:
        print(ex_fr.sub(fr, ex_ptr.sub(ptr, line)), end=''')
    '';
  } ''
    ${pkgs.python310}/bin/python "$scriptPath" < "${s}" > "$out"
  '';
  zones = pkgs.linkFarm "pdns-bind-zones" (mapAttrsToList (n: o: rec {
    name = "${n}.zone";
    path = if o.template then templateZone n o.path else o.path;
  }) cfg.auth.bind.zones);

  enableFileRecSSH = cfg.auth.bind.file-records.sshKey != null;
in
{
  options.my.pdns = with lib.types; {
    auth = {
      enable = mkBoolOpt' false "Whether to enable PowerDNS authoritative nameserver.";
      settings = mkOpt' configType { } "Authoritative server settings.";
      extraSettingsFile = extraSettingsOpt;

      bind = {
        options = {
          also-notify = bindAlsoNotify;
        };
        zones = mkOpt' (attrsOf (submodule bindZoneOpts)) { } "BIND-style zones definitions.";
        file-records = {
          sshKey = mkOpt' (nullOr str) null "SSH public key for file record update user.";
        };
      };
    };

    recursor = {
      enable = mkBoolOpt' false "Whether to enable PowerDNS recursive nameserver.";
      extraSettingsFile = extraSettingsOpt;
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

      users.users."pdns-file-records" =
      let
        script = pkgs.writeShellScript "pdns-file-records-ssh.sh" ''
          read -r -a args <<< "$SSH_ORIGINAL_COMMAND"
          exec ${pdns-file-record}/bin/pdns-file-record "''${args[@]}"
        '';
      in
      (mkIf enableFileRecSSH {
        group = "pdns";
        isSystemUser = true;
        shell = pkgs.bashInteractive;
        openssh.authorizedKeys.keys = [
          ''command="${script}" ${cfg.auth.bind.file-records.sshKey}''
        ];
      });

      environment = {
        # For pdns_control etc
        systemPackages = with pkgs; [
          pdns
          pdns-file-record
        ];

        etc."pdns-bind-zones".source = "${zones}/*";
      };

      systemd.services.pdns = {
        preStart = ''
          ${generateSettings "auth" baseAuthSettings "/run/pdns/pdns.conf"}

          source ${loadZonesCommon}

          mkdir /run/pdns/{bind-zones,file-records}
          mkdir -p /var/lib/pdns/bind-zones
          loadZones start
        '';
        postStart = ''
          chmod -R g+w /run/pdns /var/lib/pdns
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
          ExecStart = [ "" "${pkgs.pdns}/bin/pdns_server --config-dir=/run/pdns --guardian=no --daemon=no --disable-syslog --log-timestamp=no --write-pid=no" ];
          RuntimeDirectory = "pdns";
          StateDirectory = "pdns";
        };
      };

      services.powerdns = {
        enable = true;
      };
    })
    (mkIf cfg.recursor.enable {
      systemd.services.pdns-recursor = {
        preStart = ''
          ${generateSettings "recursor" baseRecursorSettings "/run/pdns-recursor/recursor.conf"}
        '';
        serviceConfig.ExecStart = [ "" "${pkgs.pdns-recursor}/bin/pdns_recursor --config-dir=/run/pdns-recursor" ];
      };

      services.pdns-recursor = {
        enable = true;
      };
    })
  ];
}
