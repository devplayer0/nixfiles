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
        useACMEHost = lib.my.pubDomain;
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
          "fw" "ctr" "oci"
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
                  ${lib.my.nginx.proxyHeaders}
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
            extraConfig = lib.my.nginx.proxyHeaders;
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

      "torrents.${lib.my.pubDomain}" = mkMerge [
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

      "jackett.${lib.my.pubDomain}" = mkMerge [
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
      "radarr.${lib.my.pubDomain}" = mkMerge [
        {
          locations."/" = mkMerge [
            {
              proxyPass = "http://jackflix-ctr.${config.networking.domain}:7878";
              proxyWebsockets = true;
              extraConfig = lib.my.nginx.proxyHeaders;
            }
            (ssoLoc "generic")
          ];
          useACMEHost = lib.my.pubDomain;
        }
        (ssoServer "generic")
      ];
      "sonarr.${lib.my.pubDomain}" = mkMerge [
        {
          locations."/" = mkMerge [
            {
              proxyPass = "http://jackflix-ctr.${config.networking.domain}:8989";
              proxyWebsockets = true;
              extraConfig = lib.my.nginx.proxyHeaders;
            }
            (ssoLoc "generic")
          ];
          useACMEHost = lib.my.pubDomain;
        }
        (ssoServer "generic")
      ];

      "jackflix.${lib.my.pubDomain}" =
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
            extraConfig = lib.my.nginx.proxyHeaders;
          };
        };
        useACMEHost = lib.my.pubDomain;
      };
    };

    minio =
    let
      host = "object-ctr.${config.networking.domain}";
      s3Upstream = "http://${host}:9000";
      extraConfig = ''
        chunked_transfer_encoding off;
        ignore_invalid_headers off;
      '';

      nixCacheableRegex = ''^\/(\S+\.narinfo|nar\/\S+\.nar\.\S+)$'';
      nixCacheHeaders = ''
        proxy_hide_header "X-Amz-Request-Id";
        add_header Cache-Control $nix_cache_control;
        add_header Expires $nix_expires;
      '';
    in
    {
      "minio.${lib.my.pubDomain}" = {
        inherit extraConfig;
        locations = {
          "/" = {
            proxyPass = "http://${host}:9001";
          };
          "/ws" = {
            proxyPass = "http://${host}:9001";
            proxyWebsockets = true;
            extraConfig = lib.my.nginx.proxyHeaders;
          };
        };
        useACMEHost = lib.my.pubDomain;
      };
      "s3.${lib.my.pubDomain}" = {
        serverAliases = [ "*.s3.${lib.my.pubDomain}" ];
        inherit extraConfig;
        locations."/".proxyPass = s3Upstream;
        useACMEHost = lib.my.pubDomain;
      };

      "nix-cache.${lib.my.pubDomain}" = {
        extraConfig = ''
          ${extraConfig}
          proxy_set_header Host "nix-cache.s3.nul.ie";
        '';
        locations = {
          "/".proxyPass = s3Upstream;
          "~ ${nixCacheableRegex}" = {
            proxyPass = s3Upstream;
            extraConfig = nixCacheHeaders;
          };
        };
        useACMEHost = lib.my.pubDomain;
        onlySSL = false;
      };
    };

    defaultsFor = mapAttrs (n: _: {
      onlySSL = mkDefault true;
      useACMEHost = mkDefault "${config.networking.domain}";
      kTLS = mkDefault true;
      http2 = mkDefault true;
    });
  in
  mkMerge [
    hosts
    (defaultsFor hosts)

    minio
    (defaultsFor minio)
  ];
}
