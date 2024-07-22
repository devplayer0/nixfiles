{ lib, pkgs, config, assignments, allAssignments, ... }:
let
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.britway) prefixes domain;

  # Can't use overrideAttrs because we need to override `vendorHash` within `buildGoModule`
  headscale = (pkgs.headscale.override {
    buildGoModule = args: pkgs.buildGoModule (args // rec {
      version = "0.23.0-alpha12";
      src = pkgs.fetchFromGitHub {
        owner = "juanfont";
        repo = "headscale";
        rev = "v${version}";
        hash = "sha256-kZZK0cXnFARxblSMz01TDcBbTorkHGAwGpR+a4/mYfU=";
      };
      patches = [];
      vendorHash = "sha256-EorT2AVwA3usly/LcNor6r5UIhLCdj3L4O4ilgTIC2o=";
      doCheck = false;
    });
  });

  pubNameservers = [
    "1.1.1.1"
    "1.0.0.1"
    "2606:4700:4700::1111"
    "2606:4700:4700::1001"
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
          database = {
            type = "sqlite3";
            sqlite.path = "/var/lib/headscale/db.sqlite3";
          };
          noise.private_key_path = "/var/lib/headscale/noise_private.key";
          prefixes = with lib.my.c.tailscale.prefix; { inherit v4 v6; };
          dns_config = {
            # Use IPs that will route inside the VPN to prevent interception
            # (e.g. DNS rebinding filtering)
            restricted_nameservers = {
              "${domain}" = pubNameservers;
              "${lib.my.c.colony.domain}" = with allAssignments.estuary.base; [
                ipv4.address ipv6.address
              ];
              "${lib.my.c.home.domain}" = with allAssignments; [
                river.hi.ipv4.address
                river.hi.ipv6.address
                stream.hi.ipv4.address
                stream.hi.ipv6.address
              ];
            };
            magic_dns = true;
            base_domain = "ts.${pubDomain}";
            override_local_dns = false;
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
          "--operator=${config.my.user.config.name}"
          "--login-server=https://ts.nul.ie"
          "--netfilter-mode=off"
          "--advertise-exit-node"
          "--accept-routes=false"
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
