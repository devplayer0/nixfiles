{ lib, pkgs, config, assignments, allAssignments, ... }:
let
  inherit (lib) concatStringsSep;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.britway) prefixes domain;

  # Can't use overrideAttrs because we need to override `vendorHash` within `buildGoModule`
  headscale = pkgs.headscale.override {
    buildGoModule = args: pkgs.buildGoModule (args // rec {
      version = "0.23.0-alpha2";
      src = pkgs.fetchFromGitHub {
        owner = "juanfont";
        repo = "headscale";
        rev = "v${version}";
        hash = "sha256-sz+uQyyq/5YYDe5I44x5x2nvd48swAhNlInB8KZYvDo=";
      };
      vendorHash = "sha256-u9AmJguQ5dnJpfhOeLN43apvMHuraOrJhvlEIp9RoIc=";
    });
  };

  advRoutes = concatStringsSep "," [
    lib.my.c.colony.prefixes.all.v4
    lib.my.c.colony.prefixes.all.v6
    lib.my.c.home.prefixes.all.v4
    lib.my.c.home.prefixes.all.v6
  ];
in
{
  config = {
    environment.systemPackages = [
      # For CLI
      config.services.headscale.package
    ];

    services = {
      headscale = {
        enable = true;
        package = headscale;
        settings = {
          disable_check_updates = true;
          unix_socket_permission = "0770";
          server_url = "https://ts.${pubDomain}";
          db_type = "sqlite3";
          db_path = "/var/lib/headscale/db.sqlite3";
          noise.private_key_path = "/var/lib/headscale/noise_private.key";
          ip_prefixes = with lib.my.c.tailscale.prefix; [ v4 v6 ];
          dns_config = {
            domains = [
              domain
              lib.my.c.colony.domain
              lib.my.c.home.domain
            ];
            nameservers = [
              "1.1.1.1"
              "1.0.0.1"
              "2606:4700:4700::1111"
              "2606:4700:4700::1001"
            ];
            magic_dns = true;
            base_domain = "ts.${pubDomain}";
            override_local_dns = true;
          };
          oidc = {
            only_start_if_oidc_is_available = true;
            issuer = "https://accounts.google.com";
            client_id = "545475967061-l45cln081mp8t4li2c34v7t7b8la6f4f.apps.googleusercontent.com";
            client_secret_path = config.age.secrets."britway/oidc-secret.txt".path;
            scope = [ "openid" "profile" "email" ];
            allowed_users = [ "jackos1998@gmail.com" ];
          };
        };
      };

      tailscale = {
        enable = true;
        authKeyFile = config.age.secrets."tailscale-auth.key".path;
        openFirewall = true;
        interfaceName = "tailscale0";
        extraUpFlags = [
          "--login-server=https://ts.nul.ie"
          "--advertise-exit-node"
          "--advertise-routes=${advRoutes}"
        ];
      };
    };

    my = {
      secrets = {
        files = {
          "britway/oidc-secret.txt" = {
            owner = "headscale";
            group = "headscale";
            mode = "440";
          };
          "tailscale-auth.key" = {};
        };
      };
    };
  };
}
