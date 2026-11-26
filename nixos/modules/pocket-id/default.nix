{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf mapAttrsToList filterAttrs;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.pocket-id;
  pocketId = config.services.pocket-id;

  groupOpts = { name, ... }: {
    options = with lib.types; {
      friendlyName = mkOpt' str name "Name shown in Pocket ID's UI.";
    };
  };

  clientOpts = { name, ... }: {
    options = with lib.types; {
      name = mkOpt' str name "Name shown to users when they sign in.";
      callbackURLs = mkOpt' (listOf str) [ ] "Allowed redirect URLs after sign-in.";
      logoutCallbackURLs = mkOpt' (listOf str) [ ] "Allowed redirect URLs after sign-out.";
      launchURL = mkOpt' (nullOr str) null "URL that Pocket ID's app list links to.";
      public = mkBoolOpt' false "Whether this is a public client (no secret).";
      pkce = mkBoolOpt' false "Whether to require PKCE.";
      allowedGroups = mkOpt' (listOf str) [ ]
        "Pocket ID groups (by name) whose members may sign in; any user may when empty.";
      secret = {
        file = mkOpt' (nullOr path) null "File holding the client secret.";
        key = mkOpt' (nullOr str) null
          "Read the secret from this key of an env file instead of the whole file.";
      };
      extraSettings = mkOpt' (attrsOf unspecified) { }
        "Extra fields of Pocket ID's client API object (e.g. `skipConsent`).";
    };
  };

  spec = pkgs.writeText "pocket-id-sync.json" (builtins.toJSON {
    groups = mapAttrsToList (n: g: { name = n; inherit (g) friendlyName; }) cfg.groups;
    clients = mapAttrsToList (id: c: {
      inherit id;
      groups = c.allowedGroups;
      secret = c.secret.file != null;
      secretKey = c.secret.key;
      settings = {
        inherit (c) name callbackURLs logoutCallbackURLs launchURL;
        isPublic = c.public;
        pkceEnabled = c.pkce;
        isGroupRestricted = c.allowedGroups != [ ];
      } // c.extraSettings;
    }) cfg.clients;
  });

  sync = pkgs.writers.writePython3 "pocket-id-sync" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./sync.py);
in
{
  options.my.pocket-id = with lib.types; {
    enable = mkBoolOpt' false "Whether to manage Pocket ID groups and OIDC clients declaratively.";
    apiKeyFile = mkOpt' path null "File holding Pocket ID's static API key (at least 16 characters).";
    groups = mkOpt' (attrsOf (submodule groupOpts)) { }
      "User groups to create; membership is managed in Pocket ID.";
    clients = mkOpt' (attrsOf (submodule clientOpts)) { } "OIDC clients, by client ID.";
  };

  config = mkIf cfg.enable {
    assertions = mapAttrsToList (id: c: {
      assertion = c.public == (c.secret.file == null);
      message = "my.pocket-id.clients.${id}: a client needs a secret unless it is public.";
    }) cfg.clients;

    services.pocket-id = {
      enable = true;
      credentials.STATIC_API_KEY = cfg.apiKeyFile;
    };

    systemd.services.pocket-id-sync = {
      description = "Pocket ID groups and OIDC clients";
      requires = [ "pocket-id.service" ];
      after = [ "pocket-id.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${sync} ${spec} http://127.0.0.1:${toString pocketId.settings.PORT}";
        DynamicUser = true;
        RuntimeDirectory = "pocket-id-sync";
        StateDirectory = "pocket-id-sync";
        LoadCredential = [ "api-key:${cfg.apiKeyFile}" ]
          ++ mapAttrsToList (id: c: "client-${id}:${c.secret.file}")
            (filterAttrs (_: c: c.secret.file != null) cfg.clients);

        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      };
    };
  };
}
