{ lib, pkgs, config, ... }:
let
  inherit (builtins) mapAttrs toJSON;
  inherit (lib) mkMerge mkDefault genAttrs flatten concatStringsSep;
  inherit (lib.my.c) pubDomain home;
  inherit (lib.my.c.nginx) proxyHeaders;
  inherit (config.networking) domain;

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
        add_header Access-Control-Allow-Origin *;
      '';
    };
    "/.well-known/webfinger".return = "301 https://toot.nul.ie$request_uri";
    "/.well-known/nodeinfo".return = "301 https://toot.nul.ie$request_uri";
    "/.well-known/host-meta".return = "301 https://toot.nul.ie$request_uri";
    "/.well-known/atproto-did".return = "301 https://pds.nul.ie$request_uri";
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
          {
            "/".root = pkgs.linkFarm "nginx-root" [
              {
                name = "index.html";
                path = ./default.html;
              }
              {
                name = "cv.pdf";
                path = builtins.fetchurl {
                  url = "https://github.com/devplayer0/cvos/releases/download/v0.1.3/bootable.pdf";
                  sha256 = "018wh6ps19n7323fi44njzj9yd4wqslc90dykbwfyscv7bgxhlar";
                };
              }
              {
                name = "ssh.pub";
                path = lib.my.c.sshKeyFiles.me;
              }
            ];
          }
          wellKnown
        ];
        useACMEHost = pubDomain;
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

      "sso.${pubDomain}" = {
        locations."/".proxyPass = config.my.nginx-sso.includes.endpoint;
        useACMEHost = pubDomain;
      };

      "netdata-colony.${pubDomain}" =
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
                proxyPass = "http://$behost.${domain}:19999/$ndpath$is_args$args";
                extraConfig = ''
                  proxy_pass_request_headers on;
                  ${proxyHeaders}
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
          useACMEHost = pubDomain;
        }
        (ssoServer "generic")
      ];

      "pass.${pubDomain}" =
      let
        upstream = "http://vaultwarden-ctr.${domain}:8080";
      in
      {
        locations = {
          "/".proxyPass = upstream;
          "/notifications/hub" = {
            proxyPass = upstream;
            proxyWebsockets = true;
            extraConfig = proxyHeaders;
          };
          "/notifications/hub/negotiate".proxyPass = upstream;
        };
        useACMEHost = pubDomain;
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
            "/".proxyPass = "http://chatterbox-ctr.${domain}:8008";
            "= /".return = "301 https://element.${pubDomain}";
          }
          wellKnown
        ];
        useACMEHost = pubDomain;
      };

      "element.${pubDomain}" =
      let
        headers = ''
          # TODO: why are these here?
          #add_header X-Frame-Options SAMEORIGIN;
          #add_header X-Content-Type-Options nosniff;
          #add_header X-XSS-Protection "1; mode=block";
          # This seems to break file downloads...
          #add_header Content-Security-Policy "frame-ancestors 'none'";
        '';
      in
      {
        extraConfig = ''
          ${headers}
        '';
        root = pkgs.element-web.override {
          # Currently it seems like single quotes aren't escaped like they should be...
          conf = {
            brand = "/dev/player0 Matrix";
            show_labs_settings = true;
            default_country_code = "IE";
            disable_guests = true;
            default_server_config = {
              "m.homeserver" = {
                base_url = "https://matrix.nul.ie";
                server_name = "nul.ie";
              };
            };
            room_directory.servers = [
              "nul.ie"
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
        useACMEHost = pubDomain;
      };

      "torrents.${pubDomain}" = mkMerge [
        {
          locations."/" = mkMerge [
            {
              proxyPass = "http://jackflix-ctr.${domain}:9091";
            }
            (ssoLoc "generic")
          ];
          useACMEHost = pubDomain;
        }
        (ssoServer "generic")
      ];

      "jackett.${pubDomain}" = mkMerge [
        {
          locations."/" = mkMerge [
            {
              proxyPass = "http://jackflix-ctr.${domain}:9117";
            }
            (ssoLoc "generic")
          ];
          useACMEHost = pubDomain;
        }
        (ssoServer "generic")
      ];
      "radarr.${pubDomain}" = mkMerge [
        {
          locations."/" = mkMerge [
            {
              proxyPass = "http://jackflix-ctr.${domain}:7878";
              proxyWebsockets = true;
              extraConfig = proxyHeaders;
            }
            (ssoLoc "generic")
          ];
          useACMEHost = pubDomain;
        }
        (ssoServer "generic")
      ];
      "sonarr.${pubDomain}" = mkMerge [
        {
          locations."/" = mkMerge [
            {
              proxyPass = "http://jackflix-ctr.${domain}:8989";
              proxyWebsockets = true;
              extraConfig = proxyHeaders;
            }
            (ssoLoc "generic")
          ];
          useACMEHost = pubDomain;
        }
        (ssoServer "generic")
      ];
      "gib.${pubDomain}" = {
        locations."/".proxyPass = "http://jackflix-ctr.${domain}:5055";
        useACMEHost = pubDomain;
      };

      "jackflix.${pubDomain}" =
      let
        upstream = "http://jackflix-ctr.${domain}:8096";
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
            extraConfig = proxyHeaders;
          };
        };
        useACMEHost = pubDomain;
      };

      "toot.nul.ie" = {
        locations."/" = {
          proxyPass = "http://toot-ctr.${domain}:80";
          proxyWebsockets = true;
          extraConfig = proxyHeaders;
        };
        useACMEHost = pubDomain;
      };

      "pds.nul.ie" = {
        locations."/" = {
          proxyPass = "http://toot-ctr.${domain}:3000";
          proxyWebsockets = true;
          extraConfig = proxyHeaders;
        };
        useACMEHost = pubDomain;
      };

      "share.${pubDomain}" = {
        locations."/" = {
          proxyPass = "http://object-ctr.${domain}:9090";
          proxyWebsockets = true;
          extraConfig = proxyHeaders;
        };
        useACMEHost = pubDomain;
      };

      "stuff.${pubDomain}" = {
        locations."/" = {
          basicAuthFile = config.age.secrets."middleman/htpasswd".path;
          root = "/mnt/media/stuff";
          extraConfig = ''
            fancyindex on;
            fancyindex_show_dotfiles on;
          '';
        };
        useACMEHost = pubDomain;
      };
      "public.${pubDomain}" = {
        onlySSL = false;
        addSSL = true;
        serverAliases = [ "p.${pubDomain}" ];
        locations."/" = {
          root = "/mnt/media/public";
          extraConfig = ''
            fancyindex on;
            fancyindex_show_dotfiles on;
          '';
        };
        useACMEHost = pubDomain;
      };

      "mc-map.${pubDomain}" = {
        locations."/".proxyPass = "http://simpcraft-oci.${domain}:8100";
        useACMEHost = pubDomain;
      };
      "mc-rail.${pubDomain}" = {
        locations."/".proxyPass = "http://simpcraft-oci.${domain}:3876";
        useACMEHost = pubDomain;
      };

      "mc-map-kink.${pubDomain}" = {
        locations."/".proxyPass = "http://kinkcraft-oci.${domain}:8100";
        useACMEHost = pubDomain;
      };

      "librespeed.${domain}" = {
        locations."/".proxyPass = "http://localhost:8989";
      };
      "speed.${pubDomain}" = {
        locations."/".proxyPass = "http://localhost:8989";
        useACMEHost = pubDomain;
      };

      "md.${pubDomain}" = {
        locations."/" = {
          proxyPass = "http://object-ctr.${domain}:3000";
          proxyWebsockets = true;
          extraConfig = proxyHeaders;
        };
        useACMEHost = pubDomain;
      };
      "pb.${pubDomain}" = {
        locations."/".proxyPass = "http://object-ctr.${domain}:8088";
        useACMEHost = pubDomain;
      };
      "photos.${pubDomain}" = {
        locations."/" = {
          proxyPass = "http://jackflix-ctr.${domain}:2342";
          proxyWebsockets = true;
          extraConfig = proxyHeaders;
        };
        useACMEHost = pubDomain;
      };

      "pront.${pubDomain}" = mkMerge [
        {
          locations."/" = mkMerge [
            {
              proxyPass = "http://stream-hi.${home.domain}:5000";
              proxyWebsockets = true;
              extraConfig = proxyHeaders;
            }
            (ssoLoc "generic")
          ];
          locations."~* ^/webcam/(.*)" = mkMerge [
            {
              proxyPass = "http://stream-hi.${home.domain}:5050/$1$is_args$args";
              extraConfig = proxyHeaders;
            }
            (ssoLoc "generic")
          ];
          useACMEHost = pubDomain;
        }
        (ssoServer "generic")
      ];
      "hass.${pubDomain}" = {
        locations."/" = {
          proxyPass = "http://hass-ctr.${home.domain}:8123";
          proxyWebsockets = true;
          extraConfig = proxyHeaders;
        };
        useACMEHost = pubDomain;
      };
    };

    minio =
    let
      host = "object-ctr.${domain}";
      s3Upstream = "http://${host}:9000";
      extraConfig = ''
        chunked_transfer_encoding off;
        ignore_invalid_headers off;
      '';

      nixCacheableRegex = ''^\/(\S+\.narinfo|nar\/\S+\.nar.*|serve\/.+)$'';
      nixCacheHeaders = ''
        add_header Cache-Control $nix_cache_control;
        add_header Expires $nix_expires;

        brotli on;
        brotli_types application/x-nix-archive;
      '';
    in
    {
      "minio.${pubDomain}" = {
        inherit extraConfig;
        locations = {
          "/" = {
            proxyPass = "http://${host}:9001";
          };
          "/ws" = {
            proxyPass = "http://${host}:9001";
            proxyWebsockets = true;
            extraConfig = proxyHeaders;
          };
        };
        useACMEHost = pubDomain;
      };
      "s3.${pubDomain}" = {
        serverAliases = [ "*.s3.${pubDomain}" ];
        inherit extraConfig;
        locations = {
          "/".proxyPass = s3Upstream;
          "/gitea/packages/" = {
            proxyPass = s3Upstream;
            # HACK: Docker images need the MIME type to be correct for the manifest but Gitea
            # doesn't tell S3... By hiding the header we can use add_header to set Content-Type
            # (normally can't be set directly)
            extraConfig = ''
              proxy_hide_header Content-Type;
              add_header Content-Type $upstream_http_content_type always;
              if ($args ~ "response-content-disposition=.+filename%3D%22manifest\.json%22") {
                add_header Content-Type "application/vnd.docker.distribution.manifest.v2+json";
              }
            '';
          };
        };
        useACMEHost = pubDomain;
      };

      "nix-cache.${pubDomain}" = {
        locations = {
          "/" = {
            proxyPass = "http://${host}:5000";
          };
          "~ ${nixCacheableRegex}" = {
            proxyPass = "http://${host}:5000";
            extraConfig = nixCacheHeaders;
          };
        };
        useACMEHost = pubDomain;
      };
    };

    defaultsFor = mapAttrs (n: _: {
      onlySSL = mkDefault true;
      useACMEHost = mkDefault "${domain}";
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
