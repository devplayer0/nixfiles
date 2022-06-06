{ lib, pkgs, config, ... }:
let
  inherit (builtins) mapAttrs;
  inherit (lib) mkMerge mkDefault;
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
