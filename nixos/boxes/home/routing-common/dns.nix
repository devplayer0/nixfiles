index: { lib, pkgs, config, assignments, allAssignments, ... }:
let
  inherit (builtins) attrNames elemAt;
  inherit (lib.my) net;
  inherit (lib.my.c.home) prefixes vips routers;

  name = elemAt routers index;
  otherIndex = 1 - index;
  otherName = elemAt routers otherIndex;

  authZones = attrNames config.my.pdns.auth.bind.zones;
in
{
  config = {
    my = {
      secrets.files = {
        "home/pdns/auth.conf" = {
          owner = "pdns";
          group = "pdns";
        };
        "home/pdns/recursor.conf" = {
          owner = "pdns-recursor";
          group = "pdns-recursor";
        };
      };

      pdns.recursor = {
        enable = true;
        extraSettingsFile = config.age.secrets."home/pdns/recursor.conf".path;
      };
    };

    services = {
      pdns-recursor = {
        dns = {
          address = [
            "127.0.0.1" "::1"
            assignments.hi.ipv4.address assignments.hi.ipv6.address
            assignments.lo.ipv4.address assignments.lo.ipv6.address
          ];
          allowFrom = [
            "127.0.0.0/8" "::1/128"
            prefixes.hi.v4 prefixes.hi.v6
            prefixes.lo.v4 prefixes.lo.v6
          ];
        };

        settings = {
          query-local-address = [
            # TODO: IPv6
            "0.0.0.0"
            "::"
            # TODO: Dynamic IPv4 WAN address?
            # assignments.internal.ipv4.address
            # assignments.internal.ipv6.address
            # assignments.hi.ipv6.address
          ];
          forward-zones = map (z: "${z}=127.0.0.1:5353") authZones;

          # DNS NOTIFY messages override TTL
          allow-notify-for = authZones;
          allow-notify-from = [ "127.0.0.0/8" "::1/128" ];

          webserver = true;
          webserver-address = "::";
          webserver-allow-from = [ "127.0.0.1" "::1" ];
        };
      };
    };

    systemd.services = {
      # Add AF_NETLINK to allow pulling IP from network interfaces
      pdns.serviceConfig.RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6 AF_NETLINK";
    };

    # For rec_control
    environment.systemPackages = with pkgs; [
      pdns-recursor
    ];

    my.pdns.auth = {
      enable = true;
      extraSettingsFile = config.age.secrets."home/pdns/auth.conf".path;
      settings = {
        primary = true;
        resolver = "127.0.0.1";
        expand-alias = true;
        local-address = [
          "0.0.0.0:5353" "[::]:5353"
        ];
        also-notify = [ "127.0.0.1" ];
        enable-lua-records = true;
        # loglevel = 7;
        # log-dns-queries = true;
        # log-dns-details = true;

        api = true;
        webserver = true;
        webserver-address = "::";
        webserver-allow-from = [ "127.0.0.1" "::1" ];
      };

      bind.zones =
      let
        names = [ "core" "hi" "lo" ];
        i = toString (index + 1);
      in
      {
        "${config.networking.domain}" = {
          type = "master";
          text = ''
            $TTL 60
            @ IN SOA ns${i}.${config.networking.domain}. dev.nul.ie. (
              @@SERIAL@@ ; serial
              3h ; refresh
              1h ; retry
              1w ; expire
              1h ; minimum
            )

            ${name} IN LUA ${lib.my.dns.ifaceA {
              inherit pkgs;
              iface = "wan";
              skipBroadcasts = [ (lib.my.netBroadcast prefixes.modem.v4) ];
            }}
            ${otherName} IN LUA ${lib.my.dns.lookupIP {
              inherit pkgs;
              hostname = "${otherName}.${config.networking.domain}";
              server = net.cidr.host (otherIndex + 1) prefixes.hi.v4;
            }}
            ${elemAt routers 0} IN AAAA ${net.cidr.host 1 prefixes.hi.v6}
            ${elemAt routers 1} IN AAAA ${net.cidr.host 2 prefixes.hi.v6}

            @ IN NS ns1
            @ IN NS ns2
            ns1 IN ALIAS ${elemAt routers 0}.${config.networking.domain}.
            ns2 IN ALIAS ${elemAt routers 1}.${config.networking.domain}.

            jim-core IN A ${net.cidr.host 10 prefixes.core.v4}
            jim IN A ${net.cidr.host 10 prefixes.hi.v4}
            jim-lo IN A ${net.cidr.host 10 prefixes.lo.v4}

            dave-core IN A ${net.cidr.host 11 prefixes.core.v4}
            dave IN A ${net.cidr.host 11 prefixes.hi.v4}
            dave-lo IN A ${net.cidr.host 11 prefixes.lo.v4}

            ups IN A ${net.cidr.host 20 prefixes.lo.v4}
            palace-kvm IN A ${net.cidr.host 21 prefixes.lo.v4}

            ${lib.my.dns.fwdRecords {
              inherit allAssignments names;
              domain = config.networking.domain;
            }}
          '';
        };
        "168.192.in-addr.arpa" = {
          type = "master";
          text = ''
            $TTL 60
            @ IN SOA ns${i}.${config.networking.domain}. dev.nul.ie. (
              @@SERIAL@@ ; serial
              3h ; refresh
              1h ; retry
              1w ; expire
              1h ; minimum
            )

            @ IN NS ns1.${config.networking.domain}.
            @ IN NS ns2.${config.networking.domain}.

            ${lib.my.dns.ptrRecords {
              inherit allAssignments names;
              domain = config.networking.domain;
              ndots = 2;
            }}
          '';
        };
        "0.d.4.0.0.c.7.9.e.0.a.2.ip6.arpa" = {
          type = "master";
          text = ''
            $TTL 60
            @ IN SOA ns${i}.${config.networking.domain}. dev.nul.ie. (
              @@SERIAL@@ ; serial
              3h ; refresh
              1h ; retry
              1w ; expire
              1h ; minimum
            )

            @ IN NS ns1.${config.networking.domain}.
            @ IN NS ns2.${config.networking.domain}.

            ${lib.my.dns.ptr6Records {
              inherit allAssignments names;
              domain = config.networking.domain;
              ndots = 20;
            }}
          '';
        };
      };
    };
  };
}