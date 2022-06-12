{ lib, pkgs, config, ... }:
let
  inherit (builtins) mapAttrs toJSON;
  inherit (lib) mkMerge mkDefault genAttrs flatten;

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

      "sso.${lib.my.pubDomain}" = {
        locations."/".proxyPass = config.my.nginx-sso.includes.endpoint;
        useACMEHost = lib.my.pubDomain;
      };

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
