{ lib, pkgs, config, assignments, allAssignments, ... }:
let
  inherit (builtins) attrNames stringLength genList filter;
  inherit (lib)
    concatStrings concatStringsSep concatMapStringsSep mapAttrsToList filterAttrs genAttrs optionalString flatten;

  ptrDots = 2;
  reverseZone = "100.10.in-addr.arpa";
  ptrDots6 = 20;
  reverseZone6 = "2.d.4.0.0.c.7.9.e.0.a.2.ip6.arpa";
  ptr6ValTrim = (stringLength "2a0e:97c0:4d2:") + 1;

  authZones = attrNames config.my.pdns.auth.bind.zones;
in
{
  config = {
    my = {
      secrets.files = {
        "estuary/pdns/auth.conf" = {
          owner = "pdns";
          group = "pdns";
        };
        "estuary/pdns/recursor.conf" = {
          owner = "pdns-recursor";
          group = "pdns-recursor";
        };

        "estuary/netdata/powerdns.conf" = {
          owner = "netdata";
          group = "netdata";
        };
        "estuary/netdata/powerdns_recursor.conf" = {
          owner = "netdata";
          group = "netdata";
        };
      };

      pdns.recursor = {
        enable = true;
        extraSettingsFile = config.age.secrets."estuary/pdns/recursor.conf".path;
      };
    };

    services = {
      netdata = {
        configDir = {
          "go.d/powerdns.conf" = config.age.secrets."estuary/netdata/powerdns.conf".path;
          "go.d/powerdns_recursor.conf" = config.age.secrets."estuary/netdata/powerdns_recursor.conf".path;
        };
      };

      pdns-recursor = {
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

        settings = {
          query-local-address = [
            assignments.internal.ipv4.address
            assignments.internal.ipv6.address
            assignments.base.ipv6.address
          ];
          forward-zones = map (z: "${z}=127.0.0.1:5353") authZones;

          # DNS NOTIFY messages override TTL
          allow-notify-for = authZones;
          allow-notify-from = [ "127.0.0.0/8" "::1/128" ];

          webserver = true;
          webserver-address = "::";
          webserver-allow-from = [ "127.0.0.1" "::1" ];

          lua-dns-script = pkgs.writeText "pdns-script.lua" ''
            function preresolve(dq)
              if dq.qname:equal("nix-cache.nul.ie") then
                dq:addAnswer(pdns.CNAME, "http.${config.networking.domain}.")
                dq.rcode = 0
                dq.followupFunction = "followCNAMERecords"
                return true
              end

              return false
            end
          '';
        };
      };
    };

    # For rec_control
    environment.systemPackages = with pkgs; [
      pdns-recursor
    ];

    my.pdns.auth = {
      enable = true;
      extraSettingsFile = config.age.secrets."estuary/pdns/auth.conf".path;
      settings = {
        primary = true;
        resolver = "127.0.0.1";
        expand-alias = true;
        local-address = [
          "0.0.0.0:5353" "[::]:5353"
        ];
        also-notify = [ "127.0.0.1" ];
        allow-axfr-ips = [
          "216.218.133.2" "2001:470:600::2"
        ];
        enable-lua-records = true;
        #loglevel = 7;
        #log-dns-queries = true;
        #log-dns-details = true;

        api = true;
        webserver = true;
        webserver-address = "::";
        webserver-allow-from = [ "127.0.0.1" "::1" ];
      };

      bind = {
        file-records.sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBSvcgbEesOgvKJLt3FLXPaLOcCIuOUYtZXXtEv6k4Yd";
      };

      bind.zones =
      let
        genRecords = assignments: f:
          concatStringsSep
            "\n"
            (filter
              (s: s != "")
              (flatten
                (map
                  (assignment: (mapAttrsToList
                    (_: as: f as."${assignment}")
                    (filterAttrs
                      (_: as: as ? "${assignment}" && as."${assignment}".visible)
                      allAssignments)))
                  assignments)));

        genFor = [ "internal" "base" "vms" "ctrs" "routing" ];
        intRecords =
          genRecords genFor (a: ''
            ${a.name} IN A ${a.ipv4.address}
            ${optionalString (a.ipv6.address != null) "${a.name} IN AAAA ${a.ipv6.address}"}
            ${concatMapStringsSep "\n" (alt: "${alt} IN CNAME ${a.name}") a.altNames}
          '');
        intPtrRecords =
          genRecords
            genFor
            (a:
              optionalString
                a.ipv4.genPTR
                ''@@PTR:${a.ipv4.address}:${toString ptrDots}@@ IN PTR ${a.name}.${config.networking.domain}.'');
        intPtr6Records =
          genRecords
            genFor
            (a:
              optionalString
                (a.ipv6.address != null && a.ipv6.genPTR)
                ''@@PTR:${a.ipv6.address}:${toString ptrDots6}@@ IN PTR ${a.name}.${config.networking.domain}.'');

        wildcardPtrDef = ''IN LUA PTR "createReverse('ip-%3%-%4%.${config.networking.domain}')"'';

        reverse6Script =
        let
         len = toString ptr6ValTrim;
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

            http IN A ${assignments.internal.ipv4.address}
            http IN AAAA ${allAssignments.middleman.internal.ipv6.address}

            valheim IN A ${assignments.internal.ipv4.address}
            valheim IN AAAA ${allAssignments.valheim-oci.internal.ipv6.address}

            andrey-cust IN A ${allAssignments.kelder.estuary.ipv4.address}

            $TTL 3
            _acme-challenge IN LUA TXT @@FILE@@

            $TTL 60
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
            @ IN NS ns1.he.net.

            ${intPtr6Records}

            * ${wildcardPtr6Def}
            ; Have to add a specific wildcard for each of the explicitly set subnets... this is disgusting for IPv6
            *.0 ${wildcardPtr6Def}
            *.0.0 ${wildcardPtr6Def}
            *.1.0.0 ${wildcardPtr6Def}

            ${wildcardPtr6Z "0.1.0.0"}
            ${wildcardPtr6Z "1.1.0.0"}
            ${wildcardPtr6Z "2.1.0.0"}
          '';
        };
      };
    };
  };
}
