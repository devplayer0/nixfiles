{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf mkMerge getBin mapAttrsToList;
  inherit (lib.my) mkOpt' mkBoolOpt';

  includeOpts = { ... }: {
    options = with lib.types; {
      auth = {
        path = mkOpt' str "/sso-auth" "HTTP path for SSO auth.";
        redirect = mkOpt' str "$scheme://$http_host$request_uri" "URL to redirect to upon successful login.";
      };
      logout = {
        path = mkOpt' str "/sso-logout" "HTTP path for SSO logout.";
        redirect = mkOpt' str "$scheme://$http_host/" "URL to redirect to upon successful logout.";
      };
    };
  };

  cfg = config.my.nginx-sso;

  pkg = getBin cfg.package;
  baseConfig = pkgs.writeText "nginx-sso.yaml" (builtins.toJSON cfg.configuration);
  runCfg = "/run/nginx-sso/config.yaml";
in
{
  options.my.nginx-sso = with lib.types; {
    enable = mkBoolOpt' true "Whether to enable custom nginx-sso.";
    package = mkOpt' package pkgs.nginx-sso "nginx-sso package to use.";
    configuration = mkOpt' (attrsOf unspecified) { } "nginx-sso configuration.";
    extraConfigFile = mkOpt' (nullOr str) null "Path to configuration (e.g. for secrets).";

    includes = {
      endpoint = mkOpt' str "http://localhost:8082" "Upstream for proxied auth requests.";
      baseURL = mkOpt' str null "Base URL for redirects.";

      instances = mkOpt' (attrsOf (submodule includeOpts)) { } "nginx includes instances.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.nginx.sso.enable;
        message = "Stock nginx-sso cannot be used with this module.";
      }
    ];

    environment.etc = with cfg.includes; mkMerge (mapAttrsToList (n: i: {
        "nginx/includes/sso/server-${n}.conf".text = ''
          location ${i.auth.path} {
            # Do not allow requests from outside
            internal;

            # Access /auth endpoint to query login state
            proxy_pass ${endpoint}/auth;

            # Do not forward the request body (nginx-sso does not care about it)
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";

            # Set custom information for ACL matching: Each one is available as
            # a field for matching: X-Host = x-host, ...
            proxy_set_header X-Origin-URI $request_uri;
            proxy_set_header X-Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          }

          # Define where to send the user to login and specify how to get back
          location @error401 {
            return 302 ${baseURL}/login?go=${i.auth.redirect};
          }

          # If the user is lead to /logout redirect them to the logout endpoint
          # of ngninx-sso which then will redirect the user to / on the current host
          location ${i.logout.path} {
            return 302 ${baseURL}/logout?go=${i.logout.redirect};
          }
        '';
        "nginx/includes/sso/location-${n}.conf".text = ''
          # Protect this location using the auth_request
          auth_request ${i.auth.path};

          # Redirect the user to the login page when they are not logged in
          error_page 401 = @error401;

          # Automatically renew SSO cookie on request
          auth_request_set $cookie $upstream_http_set_cookie;
          add_header Set-Cookie $cookie;
        '';
      }) instances);

    users = {
      groups.nginx-sso = {};
      users.nginx-sso = {
        group = "nginx-sso";
        isSystemUser = true;
      };
    };

    systemd.services.nginx-sso = {
      description = "Nginx SSO Backend";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      preStart = ''
        umask 066
      ${if (cfg.extraConfigFile != null) then ''
        ${pkgs.yq-go}/bin/yq -P '. *= load("${cfg.extraConfigFile}")' "${baseConfig}" > ${runCfg}
      '' else ''
        ${pkgs.yq-go}/bin/yq -P "${baseConfig}" > ${runCfg}
      ''}
      '';
      serviceConfig = {
        RuntimeDirectory = "nginx-sso";
        User = "nginx-sso";
        Group = "nginx-sso";
        ExecStart = [
          # Specify twice to clear original value
          ""
          ''${pkg}/bin/nginx-sso --frontend-dir ${pkg}/share/frontend --config ${runCfg}''
        ];
      };
    };
  };
}
