{ lib, pkgs, config, ... }:
let
  inherit (builtins) mapAttrs;
  inherit (lib) mkMerge mkDefault;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.nginx) baseHttpConfig proxyHeaders;
in
{
  config = {
    my = {
      secrets.files = {
        "dhparams.pem" = {
          owner = "acme";
          group = "acme";
          mode = "440";
        };
        "britway/cloudflare-credentials.conf" = {
          owner = "acme";
          group = "acme";
        };
      };

      firewall = {
        tcp.allowed = [ "http" "https" ];
      };
    };

    users = {
      users = {
        nginx.extraGroups = [ "acme" ];
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "dev@nul.ie";
        server = "https://acme-v02.api.letsencrypt.org/directory";
        reloadServices = [ "nginx" ];
        dnsResolver = "8.8.8.8";
      };
      certs = {
        "${pubDomain}" = {
          extraDomainNames = [
            "*.${pubDomain}"
          ];
          dnsProvider = "cloudflare";
          credentialsFile = config.age.secrets."britway/cloudflare-credentials.conf".path;
        };
      };
    };

    services = {
      nginx = {
        enable = true;
        enableReload = true;

        logError = "stderr info";
        recommendedTlsSettings = true;
        serverTokens = true;
        sslDhparam = config.age.secrets."dhparams.pem".path;

        # Based on recommended*Settings, but probably better to be explicit about these
        appendHttpConfig = ''
          ${baseHttpConfig}

          # caching
          proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=CACHE:10m inactive=7d max_size=512m;
        '';

        virtualHosts =
        let
          hosts = {
            "_" = {
              default = true;
              forceSSL = true;
              onlySSL = false;
              locations = {
                "/".root = "${pkgs.nginx}/html";
              };
            };

            "hs.${pubDomain}" = {
              locations."/" = {
                proxyPass = "http://localhost:${toString config.services.headscale.port}";
                proxyWebsockets = true;
                extraConfig = ''
                  proxy_buffering off;
                  add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
                '';
              };
            };
          };

          defaultsFor = mapAttrs (n: _: {
            onlySSL = mkDefault true;
            useACMEHost = mkDefault pubDomain;
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
