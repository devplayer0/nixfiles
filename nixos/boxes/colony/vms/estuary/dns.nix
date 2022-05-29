{ lib, pkgs, config, assignments, allAssignments, ... }:
let
  inherit (builtins) attrNames;
  inherit (lib) concatStringsSep concatMapStringsSep mapAttrsToList filterAttrs genAttrs optional;

  ptrDots = 2;
  reverseZone = "100.10.in-addr.arpa";
  ptrDots6 = 17;
  reverseZone6 = "b.b.b.0.d.4.0.0.c.7.9.e.0.a.2.ip6.arpa";

  authZones = attrNames config.my.pdns.auth.bind.zones;
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
      };

      bind.zones =
      let
        genRecords = f:
          concatStringsSep
            "\n"
            (mapAttrsToList
              (_: as: f as.internal)
              (filterAttrs (_: as: as ? "internal" && as.internal.visible) allAssignments));

        intRecords =
          genRecords (a: ''
            ${a.name} IN A ${a.ipv4.address}
            ${a.name} IN AAAA ${a.ipv6.address}
            ${concatMapStringsSep "\n" (alt: "${alt} IN CNAME ${a.name}") a.altNames}
          '');
        intPtrRecords =
          genRecords (a: ''@@PTR:${a.ipv4.address}:${toString ptrDots}@@ IN PTR ${a.name}.${config.networking.domain}.'');
        intPtr6Records =
          genRecords (a: ''@@PTR:${a.ipv6.address}:${toString ptrDots6}@@ IN PTR ${a.name}.${config.networking.domain}.'');
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

            ${intRecords}
          '';
        };
        "${reverseZone}" = {
          type = "master";
          text = ''
            $TTL 60
            @ IN SOA ns.${config.networking.domain}. dev.nul.ie (
                @@SERIAL@@ ; serial
                3h ; refresh
                1h ; retry
                1w ; expire
                1h ; minimum
              )

            @ IN NS ns.${config.networking.domain}.

            ${intPtrRecords}
          '';
        };
        "${reverseZone6}" = {
          type = "master";
          text = ''
            $TTL 60
            @ IN SOA ns.${config.networking.domain}. dev.nul.ie (
                @@SERIAL@@ ; serial
                3h ; refresh
                1h ; retry
                1w ; expire
                1h ; minimum
              )

            @ IN NS ns.${config.networking.domain}.

            ${intPtr6Records}
          '';
        };
      };
    };
  };
}
