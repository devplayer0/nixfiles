{ lib, pkgs, config, allAssignments, ... }:
let
  inherit (lib) mkMerge mkIf;
in
{
  config = {
    my = {
      secrets.files = {
        "kelder/htpasswd" = {
          owner = "nginx";
          group = "nginx";
        };
      };

      firewall = {
        tcp.allowed = [ "http" "https" ];
      };
    };

    services = {
      nginx = {
        enable = true;
        enableReload = true;

        recommendedTlsSettings = true;
        clientMaxBodySize = "0";
        serverTokens = true;

        # Based on recommended*Settings, but probably better to be explicit about these
        appendHttpConfig = ''
          # NixOS provides a logrotate config that auto-compresses :)
          log_format main
            '$remote_addr - $remote_user [$time_local] $scheme "$host" "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"';
          access_log /var/log/nginx/access.log main;

          # optimisation
          sendfile on;
          tcp_nopush on;
          tcp_nodelay on;
          keepalive_timeout 65;

          # gzip
          gzip on;
          gzip_proxied any;
          gzip_comp_level 5;
          gzip_types
            application/atom+xml
            application/javascript
            application/json
            application/xml
            application/xml+rss
            image/svg+xml
            text/css
            text/javascript
            text/plain
            text/xml;
          gzip_vary on;

          # proxying
          proxy_buffering off;
          proxy_redirect off;
          proxy_connect_timeout 60s;
          proxy_read_timeout 60s;
          proxy_send_timeout 60s;
          proxy_http_version 1.1;

          ${lib.my.nginx.proxyHeaders}

          # caching
          proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=CACHE:10m inactive=7d max_size=4g;
        '';

        virtualHosts =
        let
          withAuth = c: mkMerge [
            {
              basicAuthFile = config.age.secrets."kelder/htpasswd".path;
            }
            c
          ];
          acquisition = "http://${allAssignments.kelder-acquisition.internal.ipv4.address}";
        in
        {
          "_" = {
            default = true;
            locations = {
              "= /".root = "${pkgs.nginx}/html";

              "~ /media/?".return = "302 $scheme://$host/web/";
              "= /web/".proxyPass = "${acquisition}:8096/web/index.html";
              "/socket" = {
                proxyPass = "${acquisition}:8096/socket";
                proxyWebsockets = true;
                extraConfig = lib.my.nginx.proxyHeaders;
              };

              "/".proxyPass = "${acquisition}:8096";
            };
          };

          "media.${lib.my.kelder.domain}" = {
            locations = {
              "/".proxyPass = "${acquisition}:8096";
              "= /".return = "302 $scheme://$host/web/";
              "= /web/".proxyPass = "${acquisition}:8096/web/index.html";
              "/socket" = {
                proxyPass = "${acquisition}:8096/socket";
                proxyWebsockets = true;
                extraConfig = lib.my.nginx.proxyHeaders;
              };
            };
          };
          "torrents.${lib.my.kelder.domain}" = withAuth {
            locations."/".proxyPass = "${acquisition}:9091";
          };
          "jackett.${lib.my.kelder.domain}" = withAuth {
            locations."/".proxyPass = "${acquisition}:9117";
          };
          "radarr.${lib.my.kelder.domain}" = withAuth {
            locations."/" = {
              proxyPass = "${acquisition}:7878";
              proxyWebsockets = true;
              extraConfig = lib.my.nginx.proxyHeaders;
            };
          };
          "sonarr.${lib.my.kelder.domain}" = withAuth {
            locations."/" = {
              proxyPass = "${acquisition}:8989";
              proxyWebsockets = true;
              extraConfig = lib.my.nginx.proxyHeaders;
            };
          };
        };
      };
    };
  };
}
