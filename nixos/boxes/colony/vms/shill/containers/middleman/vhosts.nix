{ lib, pkgs, config, ... }:
let
  inherit (builtins) mapAttrs toJSON;
  inherit (lib) mkMerge mkDefault genAttrs flatten concatStringsSep;

  dualStackListen' = l: map (addr: l // { inherit addr; }) [ "0.0.0.0" "[::]" ];
  dualStackListen = ll: flatten (map dualStackListen' ll);

  ssoServer = i: {
    extraConfig = ''
      include /etc/nginx/includes/sso/server-${i}.conf;
    '';
  };
  ssoLoc = i: {
    extraConfig = ''
      include /etc/nginx/includes/sso/location-${i}.conf;
    '';
  };

  mkWellKnown = type: content: pkgs.writeTextFile {
    name = "well-known-${type}";
    destination = "/${type}";
    text = content;
  };
  wellKnownRoot = pkgs.symlinkJoin {
    name = "http-wellknown";
    paths = [
      # For federation
      (mkWellKnown "matrix/server" (toJSON {
        "m.server" = "matrix.nul.ie:443";
      }))
      # For clients
      (mkWellKnown "matrix/client" (toJSON {
        "m.homeserver".base_url = "https://matrix.nul.ie";
      }))
    ];
  };
  wellKnown = {
    "/.well-known/" = {
      alias = "${wellKnownRoot}/";
      extraConfig = ''
        autoindex on;
      '';
    };
  };
in
{
  my = {
    nginx-sso.includes.instances = {
      generic = {};
    };
  };

  services.nginx.virtualHosts =
  let
    hosts = {
      "_" = {
        default = true;
        forceSSL = true;
        onlySSL = false;
        locations = mkMerge [
          { }
          wellKnown
        ];
      };
      "localhost" = {
        forceSSL = false;
        onlySSL = false;
        locations = {
          "/status".extraConfig = ''
            access_log off;
            allow 127.0.0.1;
            allow ::1;
            deny all;

            vhost_traffic_status_display;
            vhost_traffic_status_display_format html;
          '';
        };
      };

      "sso.${lib.my.pubDomain}" = {
        locations."/".proxyPass = config.my.nginx-sso.includes.endpoint;
        useACMEHost = lib.my.pubDomain;
      };

      "netdata-colony.${lib.my.pubDomain}" =
      let
        hosts = [
          "vm"
          "fw" "ctr"
          "http" "jackflix-ctr" "chatterbox-ctr" "colony-psql-ctr"
        ];
        matchHosts = concatStringsSep "|" hosts;
      in
      mkMerge [
        {
          locations = {
            "= /".return = "301 https://$host/vm/";
            "~ /(?<behost>${matchHosts})$".return = "301 https://$host/$behost/";
            "~ /(?<behost>${matchHosts})/(?<ndpath>.*)" = mkMerge [
              {
                proxyPass = "http://$behost.${config.networking.domain}:19999/$ndpath$is_args$args";
                extraConfig = ''
                  proxy_pass_request_headers on;
                  proxy_set_header Connection "keep-alive";
                  proxy_store off;

                  gzip on;
                  gzip_proxied any;
                  gzip_types *;
                '';
              }
              (ssoLoc "generic")
            ];
          };
          useACMEHost = lib.my.pubDomain;
        }
        (ssoServer "generic")
      ];

      "pass.${lib.my.pubDomain}" =
      let
        upstream = "http://vaultwarden-ctr.${config.networking.domain}";
      in
      {
        locations = {
          "/".proxyPass = upstream;
          "/notifications/hub" = {
            proxyPass = upstream;
            proxyWebsockets = true;
          };
          "/notifications/hub/negotiate".proxyPass = upstream;
        };
        useACMEHost = lib.my.pubDomain;
      };

      "matrix.nul.ie" = {
        listen = dualStackListen [
          {
            port = 443;
            ssl = true;
          }
          {
            # Matrix federation
            port = 8448;
            ssl = true;
            extraParameters = [ "default_server" ];
          }
        ];
        locations = mkMerge [
          {
            "/".proxyPass = "http://chatterbox-ctr.${config.networking.domain}:8008";
            "= /".return = "301 https://element.${lib.my.pubDomain}";
          }
          wellKnown
        ];
        useACMEHost = lib.my.pubDomain;
      };

      "element.${lib.my.pubDomain}" =
      let
        headers = ''
          add_header X-Frame-Options SAMEORIGIN;
          add_header X-Content-Type-Options nosniff;
          add_header X-XSS-Protection "1; mode=block";
          add_header Content-Security-Policy "frame-ancestors 'none'";
        '';
      in
      {
        extraConfig = ''
          ${headers}
        '';
        root = pkgs.element-web.override {
          conf = {
            brand = "/dev/player0's Matrix";
            showLabsSettings = true;
            disable_guests = true;
            default_server_config = {
              "m.homeserver" = {
                base_url = "https://matrix.nul.ie";
                server_name = "nul.ie";
              };
            };
            roomDirectory.servers = [
              "nul.ie"
              "netsoc.ie"
              "matrix.org"
            ];
          };
        };
        locations = mkMerge [
          { }
          (genAttrs [ "= /index.html" "= /version" "/config" ] (_: {
            extraConfig = ''
              # Gotta duplicate the headers...
              # https://github.com/yandex/gixy/blob/master/docs/en/plugins/addheaderredefinition.md
              ${headers}
              add_header Cache-Control "no-cache";
            '';
          }))
        ];
        useACMEHost = lib.my.pubDomain;
      };

      "torrents-test.${lib.my.pubDomain}" = mkMerge [
        {
          locations."/" = mkMerge [
            {
              proxyPass = "http://jackflix-ctr.${config.networking.domain}:9091";
            }
            (ssoLoc "generic")
          ];
          useACMEHost = lib.my.pubDomain;
        }
        (ssoServer "generic")
      ];

      "jackett-test.${lib.my.pubDomain}" = mkMerge [
        {
          locations."/" = mkMerge [
            {
              proxyPass = "http://jackflix-ctr.${config.networking.domain}:9117";
            }
            (ssoLoc "generic")
          ];
          useACMEHost = lib.my.pubDomain;
        }
        (ssoServer "generic")
      ];
      "radarr-test.${lib.my.pubDomain}" = mkMerge [
        {
          locations."/" = mkMerge [
            {
              proxyPass = "http://jackflix-ctr.${config.networking.domain}:7878";
              proxyWebsockets = true;
            }
            (ssoLoc "generic")
          ];
          useACMEHost = lib.my.pubDomain;
        }
        (ssoServer "generic")
      ];
      "sonarr-test.${lib.my.pubDomain}" = mkMerge [
        {
          locations."/" = mkMerge [
            {
              proxyPass = "http://jackflix-ctr.${config.networking.domain}:8989";
              proxyWebsockets = true;
            }
            (ssoLoc "generic")
          ];
          useACMEHost = lib.my.pubDomain;
        }
        (ssoServer "generic")
      ];

      "jackflix-test.${lib.my.pubDomain}" =
      let
        upstream = "http://jackflix-ctr.${config.networking.domain}:8096";
      in
      {
        extraConfig = ''
          add_header X-Frame-Options "SAMEORIGIN";
          add_header X-XSS-Protection "1; mode=block";
          add_header X-Content-Type-Options "nosniff";
        '';
        locations = {
          "/".proxyPass = upstream;

          "= /".return = "302 https://$host/web/";
          "= /web/".proxyPass = "${upstream}/web/index.html";

          "/socket" = {
            proxyPass = upstream;
            proxyWebsockets = true;
          };
        };
        useACMEHost = lib.my.pubDomain;
      };
    };
  in
  mkMerge [
    hosts
    (mapAttrs (n: _: {
      onlySSL = mkDefault true;
      useACMEHost = mkDefault "${config.networking.domain}";
      kTLS = mkDefault true;
      http2 = mkDefault true;
    }) hosts)
  ];
}
