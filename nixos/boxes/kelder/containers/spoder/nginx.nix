{ lib, pkgs, config, allAssignments, ... }:
let
  inherit (builtins) mapAttrs;
  inherit (lib) mkMerge mkIf mkDefault;
  inherit (lib.my.c.nginx) proxyHeaders;
  inherit (lib.my.c.kelder) domain;
in
{
  config = {
    my = {
      secrets.files = {
        "kelder/htpasswd" = {
          owner = "nginx";
          group = "nginx";
        };
        "dhparams.pem" = {
          owner = "acme";
          group = "acme";
          mode = "440";
        };
      };

      firewall = {
        tcp.allowed = [ "http" "https" ];
      };
    };

    services = {
      nginx = {
        package = pkgs.openresty;
        enable = true;
        enableReload = true;

        logError = "stderr info";
        recommendedTlsSettings = true;
        clientMaxBodySize = "0";
        serverTokens = true;
        sslDhparam = config.age.secrets."dhparams.pem".path;

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

          ${proxyHeaders}

          # caching
          proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=CACHE:10m inactive=7d max_size=4g;

          init_worker_by_lua_block {
            local update_ip = function(premature)
              if premature then
                return
              end

              local hdl, err = io.popen("${pkgs.curl}/bin/curl -s https://v4.ident.me")
              if not hdl then
                ngx.log(ngx.ERR, "failed to run command: ", err)
                return
              end

              local ip, err = hdl:read("*l")
              hdl:close()
              if not ip then
                ngx.log(ngx.ERR, "failed to read ip: ", err)
                return
              end

              pub_ip = ip
              ngx.log(ngx.INFO, "ip is now: ", pub_ip)
            end

            local hdl, err = ngx.timer.every(5 * 60, update_ip)
            if not hdl then
              ngx.log(ngx.ERR, "failed to create timer: ", err)
            end
            update_ip()
          }
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
          localRedirect = to: ''
            rewrite_by_lua_block {
              if ngx.var.remote_addr == pub_ip then
                ngx.redirect(ngx.var.scheme .. "://${to}" .. ngx.var.request_uri, ngx.HTTP_MOVED_PERMANENTLY)
              end
            }
          '';
          hosts = {
            "_" = {
              default = true;
              forceSSL = true;
              onlySSL = false;
              locations = {
                "/".root = "${pkgs.nginx}/html";
              };
            };

            "monitor.${domain}" = withAuth {
              serverAliases = [ "monitor-local.${domain}" ];
              extraConfig = localRedirect "monitor-local.${domain}";
              locations = {
                "/" = {
                  proxyPass = "http://${allAssignments.kelder.ctrs.ipv4.address}:19999";
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
            };

            "kontent.${domain}" = {
              serverAliases = [ "kontent-local.${domain}" ];
              locations = {
                "/".proxyPass = "${acquisition}:8096";
                "= /".return = "302 $scheme://$host/web/";
                "= /web/".proxyPass = "${acquisition}:8096/web/index.html";
                "/socket" = {
                  proxyPass = "${acquisition}:8096/socket";
                  proxyWebsockets = true;
                  extraConfig = proxyHeaders;
                };
              };
            };
            "torrents.${domain}" = withAuth {
              serverAliases = [ "torrents-local.${domain}" ];
              extraConfig = localRedirect "torrents-local.${domain}";
              locations."/".proxyPass = "${acquisition}:9091";
            };
            "jackett.${domain}" = withAuth {
              serverAliases = [ "jackett-local.${domain}" ];
              extraConfig = localRedirect "jackett-local.${domain}";
              locations."/".proxyPass = "${acquisition}:9117";
            };
            "radarr.${domain}" = withAuth {
              serverAliases = [ "radarr-local.${domain}" ];
              extraConfig = localRedirect "radarr-local.${domain}";
              locations."/" = {
                proxyPass = "${acquisition}:7878";
                proxyWebsockets = true;
                extraConfig = proxyHeaders;
              };
            };
            "sonarr.${domain}" = withAuth {
              serverAliases = [ "sonarr-local.${domain}" ];
              extraConfig = localRedirect "sonarr-local.${domain}";
              locations."/" = {
                proxyPass = "${acquisition}:8989";
                proxyWebsockets = true;
                extraConfig = proxyHeaders;
              };
            };

            "cloud.${domain}" = {
              serverAliases = [ "cloud-local.${domain}" ];
            };
          };

          defaultsFor = mapAttrs (n: _: {
            onlySSL = mkDefault true;
            useACMEHost = mkDefault domain;
            kTLS = mkDefault true;
            http2 = mkDefault true;
          });
        in
        mkMerge [
          hosts
          (defaultsFor hosts)
        ];
      };
    };
  };
}
