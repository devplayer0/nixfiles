{ lib, pkgs, config, ... }:
let
  inherit (builtins) mapAttrs toJSON;
  inherit (lib) mkMerge mkDefault genAttrs flatten concatStringsSep;
  inherit (lib.my.c) pubDomain home;
  inherit (lib.my.c.nginx) proxyHeaders;
  inherit (config.networking) domain;

  dualStackListen' = l: map (addr: l // { inherit addr; }) [ "0.0.0.0" "[::]" ];
  dualStackListen = ll: flatten (map dualStackListen' ll);

  # Gate a vhost behind oauth2-proxy, for members of any of the given Pocket ID groups. The
  # session cookie is host-only, so other `.nul.ie` sites never see it; Pocket ID's own session
  # makes signing in to the next gated vhost a redirect.
  oauth2Proxy = config.services.oauth2-proxy.httpAddress;
  ssoServer = groups: {
    locations = {
      "^~ /oauth2/" = {
        proxyPass = oauth2Proxy;
        extraConfig = ''
          auth_request off;
          ${proxyHeaders}
          # Where to return after signing in; on a 401 this is still the original request
          proxy_set_header X-Auth-Request-Redirect $request_uri;
        '';
      };
      # A literal `proxy_pass`: `proxyPass` sets `$nix_proxy_target`, which this subrequest would
      # overwrite for the main request too
      "= /oauth2/auth".extraConfig = ''
        proxy_pass ${oauth2Proxy}/oauth2/auth?allowed_groups=${concatStringsSep "," groups};
        internal;
        auth_request off;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        ${proxyHeaders}
      '';
    };
    # A location with its own `add_header` would drop the refreshed cookie
    extraConfig = ''
      auth_request /oauth2/auth;
      error_page 401 = /oauth2/start;

      # Pass on the session cookie when a check refreshes it
      auth_request_set $sso_cookie $upstream_http_set_cookie;
      add_header Set-Cookie $sso_cookie;
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
  # Paseo's web app, which connects to daemons through the relay
  paseoWebUi = pkgs.runCommand "paseo-web-ui-${pkgs.paseo.version}" { } ''
    cp -r ${pkgs.paseo}/lib/paseo/packages/server/dist/server/web-ui "$out"
  '';

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
            "~ /(?<behost>${matchHosts})/(?<ndpath>.*)" = {
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
            };
          };
          useACMEHost = pubDomain;
        }
        (ssoServer [ "admins" ])
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
          locations."/".proxyPass = "http://jackflix-ctr.${domain}:9091";
          useACMEHost = pubDomain;
        }
        (ssoServer [ "admins" ])
      ];

      "jackett.${pubDomain}" = mkMerge [
        {
          locations."/".proxyPass = "http://jackflix-ctr.${domain}:9117";
          useACMEHost = pubDomain;
        }
        (ssoServer [ "admins" ])
      ];
      "radarr.${pubDomain}" = mkMerge [
        {
          locations."/" = {
            proxyPass = "http://jackflix-ctr.${domain}:7878";
            proxyWebsockets = true;
            extraConfig = proxyHeaders;
          };
          useACMEHost = pubDomain;
        }
        (ssoServer [ "admins" ])
      ];
      "sonarr.${pubDomain}" = mkMerge [
        {
          locations."/" = {
            proxyPass = "http://jackflix-ctr.${domain}:8989";
            proxyWebsockets = true;
            extraConfig = proxyHeaders;
          };
          useACMEHost = pubDomain;
        }
        (ssoServer [ "admins" ])
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

      "stuff.${pubDomain}" = {
        locations."/" = {
          proxyPass = "http://jackflix-ctr.${domain}:3923";
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

      "paseo-relay.${pubDomain}" = {
        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:${toString config.my.paseo-relay.port}";
            proxyWebsockets = true;
            extraConfig = ''
              ${proxyHeaders}
              proxy_read_timeout 1h;
              proxy_send_timeout 1h;
            '';
          };
          "= /metrics".return = "404";
        };
        useACMEHost = pubDomain;
      };
      "slop.${pubDomain}" = {
        root = paseoWebUi;
        extraConfig = ''
          gzip_static on;
          brotli_static on;
        '';
        locations = {
          "/".tryFiles = "$uri $uri/ /index.html";
          "= /index.html".extraConfig = ''
            add_header Cache-Control "no-store";
          '';
          "/_expo/".extraConfig = ''
            add_header Cache-Control "public, max-age=31536000, immutable";
          '';
        };
        useACMEHost = pubDomain;
      };

      # `slop-broker`'s approvals web app, which handles sign-in itself
      "approve.slop.${pubDomain}" = {
        locations."/" = {
          proxyPass = "http://palace.${home.domain}:8095";
          extraConfig = proxyHeaders;
        };
        useACMEHost = pubDomain;
      };

      "id.${pubDomain}" =
      let
        # API keys (including `pocket-id-sync`'s admin key) only work from inside
        pocketIdHeaders = ''
          ${proxyHeaders}
          proxy_set_header X-API-Key "";
        '';
        pocketId = {
          proxyPass = "http://127.0.0.1:${toString config.services.pocket-id.settings.PORT}";
          extraConfig = pocketIdHeaders;
        };
      in
      {
        locations = {
          "/" = pocketId;
          # Creating the first admin account is only possible from inside
          "~ ^/(setup|api/signup/setup)$" = pocketId // {
            extraConfig = ''
              ${concatStringsSep "\n" (map (n: "allow ${n};") (with lib.my.c.internalNets; v4 ++ v6))}
              deny all;
              ${pocketIdHeaders}
            '';
          };
        };
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
          locations."/" = {
            proxyPass = "http://stream-hi.${home.domain}:5000";
            proxyWebsockets = true;
            extraConfig = proxyHeaders;
          };
          locations."~* ^/webcam/(.*)" = {
            proxyPass = "http://stream-hi.${home.domain}:5050/$1$is_args$args";
            extraConfig = proxyHeaders;
          };
          useACMEHost = pubDomain;
        }
        (ssoServer [ "admins" ])
      ];
      "hass.${pubDomain}" = {
        locations."/" = {
          proxyPass = "http://hass-ctr.${home.domain}:8123";
          proxyWebsockets = true;
          extraConfig = proxyHeaders;
        };
        useACMEHost = pubDomain;
      };
      "hass-john.${pubDomain}" = {
        locations."/" = {
          proxyPass = "http://john-valorant-tun.${domain}:8123";
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
