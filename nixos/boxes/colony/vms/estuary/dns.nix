{ lib, pkgs, config, assignments, allAssignments, ... }:
let
  inherit (builtins) attrNames stringLength genList filter;
  inherit (lib)
    concatStrings concatStringsSep concatMapStringsSep mapAttrsToList filterAttrs genAttrs optional optionalString;

  ptrDots = 2;
  reverseZone = "100.10.in-addr.arpa";
  ptrDots6 = 17;
  reverseZone6 = "b.b.b.0.d.4.0.0.c.7.9.e.0.a.2.ip6.arpa";

  authZones = attrNames config.my.pdns.auth.bind.zones;

  pdns-file-record = pkgs.writeShellApplication {
    name = "pdns-file-record";
    runtimeInputs = [ pkgs.gnused ];
    text = ''
      die() {
        echo "$@" >&2
        exit 1
      }
      usage() {
        die "usage: $0 <add|del> <fqdn> [content]"
      }

      add() {
        if [ $# -ne 2 ]; then
          usage
        fi

        echo "$2" >> "$dir"/"$1"txt
      }
      del() {
        if [ $# -lt 1 ]; then
          usage
        fi

        file="$dir"/"$1"txt
        if [ $# -eq 1 ]; then
          rm "$file"
        else
          sed -i "/^""$2""$/!{q1}; /^""$2""$/d" "$file"
          exit $?
        fi
      }

      dir=/run/pdns/file-records
      mkdir -p "$dir"

      if [ $# -lt 1 ]; then
        usage
      fi
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
    '';
  };
in
{
  config = {
    services.pdns-recursor = {
      enable = true;
      dns = {
        address = [
          "127.0.0.1" "::1"
          assignments.base.ipv4.address assignments.base.ipv6.address
        ];
        allowFrom = [
          "127.0.0.0/8" "::1/128"
          lib.my.colony.prefixes.all.v4 lib.my.colony.prefixes.all.v6
        ];
      };
      forwardZones = genAttrs authZones (_: "127.0.0.1:5353");

      settings = {
        query-local-address = [ "0.0.0.0" "::" ];

        # DNS NOTIFY messages override TTL
        allow-notify-for = authZones;
        allow-notify-from = [ "127.0.0.0/8" "::1/128" ];
      };
    };
    # For rec_control
    environment.systemPackages = with pkgs; [
      pdns-recursor
      pdns-file-record
    ];

    my.pdns.auth = {
      enable = true;
      settings = {
        primary = true;
        resolver = "127.0.0.1";
        expand-alias = true;
        local-address = [
          "0.0.0.0:5353" "[::]:5353"
        ];
        also-notify = [ "127.0.0.1" ];
        enable-lua-records = true;
        #loglevel = 7;
        #log-dns-queries = true;
        #log-dns-details = true;
      };

      bind.zones =
      let
        genRecords = f:
          concatStringsSep
            "\n"
            (filter (s: s != "")
              (mapAttrsToList
                (_: as: f as.internal)
                (filterAttrs (_: as: as ? "internal" && as.internal.visible) allAssignments)));

        intRecords =
          genRecords (a: ''
            ${a.name} IN A ${a.ipv4.address}
            ${a.name} IN AAAA ${a.ipv6.address}
            ${concatMapStringsSep "\n" (alt: "${alt} IN CNAME ${a.name}") a.altNames}
          '');
        intPtrRecords =
          genRecords
            (a:
              optionalString
                a.ipv4.genPTR
                ''@@PTR:${a.ipv4.address}:${toString ptrDots}@@ IN PTR ${a.name}.${config.networking.domain}.'');
        intPtr6Records =
          genRecords
            (a:
              optionalString
                a.ipv4.genPTR
                ''@@PTR:${a.ipv6.address}:${toString ptrDots6}@@ IN PTR ${a.name}.${config.networking.domain}.'');

        wildcardPtrDef = ''IN LUA PTR "createReverse('ip-%3%-%4%.${config.networking.domain}')"'';

        reverse6Script =
        let
         len = toString (stringLength lib.my.colony.start.base.v6);
        in
        pkgs.writeText "reverse6.lua" ''
          local root = newDN("ip6.arpa.")
          local ptr = qname:makeRelative(root):toStringNoDot()
          local nibbles = string.gsub(string.reverse(ptr), "%.", "")

          local ip6 = string.sub(nibbles, 1, 4)
          for i = 1, 7 do
            ip6 = ip6 .. ":" .. string.sub(nibbles, (i*4)+1, (i+1)*4)
          end

          local addr = newCA(ip6)
          return "ip6-" .. string.sub(string.gsub(addr:toString(), ":", "-"), ${len}) .. ".${config.networking.domain}."
        '';
        wildcardPtr6Def = ''IN LUA PTR "dofile('${reverse6Script}')"'';
        wildcardPtr6Zeroes = n: concatStrings (genList (_: "0.") n);
        wildcardPtr6' = n: root: ''*.${wildcardPtr6Zeroes n}${root} ${wildcardPtr6Def}'';
        wildcardPtr6 = n: root: concatStringsSep "\n" (genList (i: wildcardPtr6' i root) (n - 1));
        wildcardPtr6Z = wildcardPtr6 ptrDots6;

        fileRecScript = pkgs.writeText "file-record.lua" ''
          local path = "/run/pdns/file-records/" .. qname:toStringNoDot() .. ".txt"
          if not os.execute("test -e " .. path) then
            return {}
          end

          local values = {}
          for line in io.lines(path) do
            table.insert(values, line)
          end
          return values
        '';
        fileRecVal = ''"dofile('${fileRecScript}')"'';
      in
      {
        "${config.networking.domain}" = {
          type = "master";
          text = ''
            $TTL 60
            @ IN SOA ns.${config.networking.domain}. dev.nul.ie. (
                @@SERIAL@@ ; serial
                3h ; refresh
                1h ; retry
                1w ; expire
                1h ; minimum
              )

            @ IN NS ns
            ns IN ALIAS ${config.networking.fqdn}.

            @ IN ALIAS ${config.networking.fqdn}.

            _acme-challenge IN LUA TXT ${fileRecVal}

            ${intRecords}
          '';
        };
        "${reverseZone}" = {
          type = "master";
          text = ''
            $TTL 60
            @ IN SOA ns.${config.networking.domain}. dev.nul.ie. (
                @@SERIAL@@ ; serial
                3h ; refresh
                1h ; retry
                1w ; expire
                1h ; minimum
              )

            @ IN NS ns.${config.networking.domain}.

            ${intPtrRecords}

            * ${wildcardPtrDef}
            ; Have to add a specific wildcard for each of the explicitly set subnets...
            *.0 ${wildcardPtrDef}
            *.1 ${wildcardPtrDef}
            *.2 ${wildcardPtrDef}
          '';
        };
        "${reverseZone6}" = {
          type = "master";
          text = ''
            $TTL 60
            @ IN SOA ns.${config.networking.domain}. dev.nul.ie. (
                @@SERIAL@@ ; serial
                3h ; refresh
                1h ; retry
                1w ; expire
                1h ; minimum
              )

            @ IN NS ns.${config.networking.domain}.

            ${intPtr6Records}

            * ${wildcardPtr6Def}
            ; Have to add a specific wildcard for each of the explicitly set subnets... this is disgusting for IPv6
            ${wildcardPtr6Z "0"}
            ${wildcardPtr6Z "1"}
            ${wildcardPtr6Z "2"}
          '';
        };
      };
    };
  };
}
