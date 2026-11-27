{ lib, config, ... }:
let
  inherit (lib) attrNames filterAttrs;
  inherit (lib.my.c) pubDomain;

  # Vhosts gated by `ssoServer` in `vhosts.nix`, each with its own `/oauth2/` endpoints
  ssoVhosts = attrNames (filterAttrs (_: v: v.locations ? "= /oauth2/auth") config.services.nginx.virtualHosts);
in
{
  my = {
    secrets.files = {
      # Pocket ID's database encryption key; it reads it through `LoadCredential`
      "middleman/pocket-id-encryption-key" = { };
      # Admin key for `pocket-id-sync`, which only works from inside (`vhosts.nix` strips it)
      "middleman/pocket-id-api-key" = { };
      # `OAUTH2_PROXY_CLIENT_SECRET` and `OAUTH2_PROXY_COOKIE_SECRET`
      "middleman/oauth2-proxy.env" = { };
      # Client secrets shared with the boxes that run the apps
      "gitea/oidc-secret.txt" = { };
      # Not deployed anywhere else: mailcow isn't NixOS, so it's pasted into its admin UI
      "mailcow/oidc-secret.txt" = { };
    };

    pocket-id = {
      enable = true;
      apiKeyFile = config.age.secrets."middleman/pocket-id-api-key".path;

      groups = {
        admins.friendlyName = "Admins";
      };

      clients = {
        # oauth2-proxy, which gates vhosts that have no sign-in of their own (`ssoServer`)
        sso = {
          name = "nul.ie SSO";
          callbackURLs = map (h: "https://${h}/oauth2/callback") ssoVhosts;
          pkce = true;
          allowedGroups = [ "admins" ];
          extraSettings.skipConsent = true;
          secret = {
            file = config.age.secrets."middleman/oauth2-proxy.env".path;
            key = "OAUTH2_PROXY_CLIENT_SECRET";
          };
        };

        # Gitea's `id.nul.ie` login source (`git` VM)
        gitea = {
          name = "Gitea";
          callbackURLs = [ "https://git.${pubDomain}/user/oauth2/id.${pubDomain}/callback" ];
          launchURL = "https://git.${pubDomain}/";
          secret.file = config.age.secrets."gitea/oidc-secret.txt".path;
        };

        # mailcow's Generic-OIDC identity provider (`mail` VM), for mailbox sign-in
        mailcow = {
          name = "mailcow";
          callbackURLs = [ "https://mail.${pubDomain}" "https://mail.${pubDomain}/" ];
          launchURL = "https://mail.${pubDomain}/";
          secret.file = config.age.secrets."mailcow/oidc-secret.txt".path;
        };
      };
    };
  };

  # oauth2-proxy talks to Pocket ID through the local nginx rather than out and back in
  networking.hosts = {
    "127.0.0.1" = [ "id.${pubDomain}" ];
    "::1" = [ "id.${pubDomain}" ];
  };

  services = {
    # Passkey-only OpenID Connect provider at `id.nul.ie`, published by nginx
    pocket-id = {
      settings = {
        APP_URL = "https://id.${pubDomain}";
        HOST = "127.0.0.1";
        PORT = 1411;
        TRUST_PROXY = true;
        ANALYTICS_DISABLED = true;
      };
      credentials.ENCRYPTION_KEY = config.age.secrets."middleman/pocket-id-encryption-key".path;
    };

    # Single sign-on for every `.nul.ie` vhost behind `ssoServer` in `vhosts.nix`
    oauth2-proxy = {
      enable = true;
      provider = "oidc";
      oidcIssuerUrl = "https://id.${pubDomain}";
      clientID = "sso";
      # On the vhost being signed in to
      redirectURL = "/oauth2/callback";
      keyFile = config.age.secrets."middleman/oauth2-proxy.env".path;
      # `offline_access` for a refresh token, so sessions can be checked again without a passkey
      scope = "openid email profile groups offline_access";
      approvalPrompt = "auto";
      # Access is decided by Pocket ID group (`allowed_groups` in `ssoServer`)
      email.domains = [ "*" ];

      httpAddress = "http://127.0.0.1:4180";
      reverseProxy = true;
      trustedProxyIP = [ "127.0.0.1" ];
      setXauthrequest = true;

      cookie = {
        # Host-only, so the cookie is only sent to the vhost it was issued for
        secure = true;
        # Sessions last a week, but Pocket ID checks the user (and their groups) every hour
        expire = "168h";
        refresh = "1h";
      };

      extraConfig = {
        code-challenge-method = "S256";
        skip-provider-button = true;
        # Pocket ID doesn't verify email addresses, and they aren't used for access here
        insecure-oidc-allow-unverified-email = true;
      };
    };
  };

  systemd.services.oauth2-proxy = {
    wants = [ "pocket-id-sync.service" ];
    after = [ "pocket-id-sync.service" "nginx.service" ];
  };
}
