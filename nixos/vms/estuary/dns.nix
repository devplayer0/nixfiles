{ lib, config, allAssignments, ... }:
let
  inherit (lib) concatStringsSep concatMapStringsSep mapAttrsToList filterAttrs optional;
in
{
  config = {
    networking.domain = "fra1.int.nul.ie";
    my.pdns.auth = {
      enable = true;
      settings = {
        primary = true;
        expand-alias = true;
        local-address = [
          "127.0.0.1:5353" "[::]:5353"
        ] ++ (optional (!config.my.build.isDevVM) "192.168.122.126");
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
          genRecords (a: ''@@PTR:${a.ipv4.address}:2@@ IN PTR ${a.name}.${config.networking.domain}.'');
        intPtr6Records =
          genRecords (a: ''@@PTR:${a.ipv6.address}:20@@ IN PTR ${a.name}.${config.networking.domain}.'');
      in
      {
        "${config.networking.domain}" = {
          type = "master";
          text = ''
            $TTL 60
            @ IN SOA ns.${config.networking.domain}. hostmaster.${config.networking.domain}. (
                @@SERIAL@@ ; serial
                3h ; refresh
                1h ; retry
                1w ; expire
                1h ; minimum
              )

            @ IN ALIAS ${config.networking.fqdn}.

            ${intRecords}
          '';
        };
        "100.10.in-addr.arpa" = {
          type = "master";
          text = ''
            $TTL 60
            @ IN SOA ns.${config.networking.domain}. hostmaster.${config.networking.domain}. (
                @@SERIAL@@ ; serial
                3h ; refresh
                1h ; retry
                1w ; expire
                1h ; minimum
              )

            ${intPtrRecords}
          '';
        };
        "1.d.4.0.0.c.7.9.e.0.a.2.ip6.arpa" = {
          type = "master";
          text = ''
            $TTL 60
            @ IN SOA ns.${config.networking.domain}. hostmaster.${config.networking.domain}. (
                @@SERIAL@@ ; serial
                3h ; refresh
                1h ; retry
                1w ; expire
                1h ; minimum
              )

            ${intPtr6Records}
          '';
        };
      };
    };
  };
}
