{ lib, pkgs, config, assignments, allAssignments, ... }:
let
  inherit (builtins) attrNames;
  inherit (lib.my) net;
  inherit (lib.my.c.colony) prefixes custRouting;

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
        "estuary/pdns/recursor.yml" = {
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
        extraSettingsFile = config.age.secrets."estuary/pdns/recursor.yml".path;
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
        yaml-settings = {
          incoming = {
            listen = [
              "127.0.0.1" "::1"
              assignments.base.ipv4.address assignments.base.ipv6.address
            ];
            allow_from = [
              "127.0.0.0/8" "::1/128"
              prefixes.all.v4 prefixes.all.v6
            ] ++ (with lib.my.c.tailscale.prefix; [ v4 v6 ]);

            # DNS NOTIFY messages override TTL
            allow_notify_for = authZones;
            allow_notify_from = [ "127.0.0.0/8" "::1/128" ];
          };

          outgoing = {
            source_address = [
              assignments.internal.ipv4.address
              assignments.internal.ipv6.address
              assignments.base.ipv6.address
            ];
          };

          recursor = {
            forward_zones = map (z: {
              zone = z;
              forwarders = [ "127.0.0.1:5353" ];
            }) authZones;

            lua_dns_script = pkgs.writeText "pdns-script.lua" ''
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

          webservice = {
            webserver = true;
            address = "::";
            allow_from = [ "127.0.0.1" "::1" ];
          };
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
        names = [ "internal" "base" "vms" "ctrs" "routing" ];
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
            librespeed IN CNAME http.${config.networking.domain}.

            valheim IN A ${assignments.internal.ipv4.address}
            valheim IN AAAA ${allAssignments.valheim-oci.internal.ipv6.address}
            simpcraft IN A ${assignments.internal.ipv4.address}
            simpcraft IN AAAA ${allAssignments.simpcraft-oci.internal.ipv6.address}
            simpcraft-staging IN A ${assignments.internal.ipv4.address}
            simpcraft-staging IN AAAA ${allAssignments.simpcraft-staging-oci.internal.ipv6.address}
            enshrouded IN A ${assignments.internal.ipv4.address}
            kevcraft IN A ${assignments.internal.ipv4.address}
            kevcraft IN AAAA ${allAssignments.kevcraft-oci.internal.ipv6.address}
            kinkcraft IN A ${assignments.internal.ipv4.address}
            kinkcraft IN AAAA ${allAssignments.kinkcraft-oci.internal.ipv6.address}

            mail-vm IN A ${net.cidr.host 0 prefixes.mail.v4}
            mail-vm IN AAAA ${net.cidr.host 1 prefixes.mail.v6}

            darts-cust IN A ${net.cidr.host 0 prefixes.darts.v4}
            darts-cust IN AAAA ${net.cidr.host 1 prefixes.darts.v6}

            andrey-cust IN A ${allAssignments.kelder.estuary.ipv4.address}

            jam-cust IN A ${net.cidr.host 0 prefixes.jam.v4}
            jam-fwd IN A ${allAssignments.shill.internal.ipv4.address}
            jam-cust IN AAAA ${net.cidr.host 1 prefixes.jam.v6}

            $TTL 3
            _acme-challenge IN LUA TXT @@FILE@@

            $TTL 60
            ${lib.my.dns.fwdRecords {
              inherit allAssignments names;
              domain = config.networking.domain;
            }}
          '';
        };
        "100.10.in-addr.arpa" = {
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

            ${lib.my.dns.ptrRecords {
              inherit allAssignments names;
              domain = config.networking.domain;
              ndots = 2;
            }}
          '';
        };
        "2.d.4.0.0.c.7.9.e.0.a.2.ip6.arpa" = {
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

            1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.2 IN PTR mail.nul.ie.

            1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.1.0.0.2 IN PTR darts-cust.${config.networking.domain}.

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
