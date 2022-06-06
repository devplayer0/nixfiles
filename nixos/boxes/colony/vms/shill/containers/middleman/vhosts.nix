{ lib, pkgs, config, ... }:
let
  inherit (builtins) mapAttrs;
  inherit (lib) mkMerge mkDefault genAttrs;
in
{
  services.nginx.virtualHosts =
  let
    hosts = {
      "_" = {
        default = true;
        forceSSL = true;
        onlySSL = false;
      };

      "pass.nul.ie" =
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
        globalRedirect = "element.nul.ie";
        useACMEHost = lib.my.pubDomain;
      };
      "element.nul.ie" =
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
