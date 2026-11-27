{ lib, pkgs, config, assignments, allAssignments, ... }:
let
  inherit (lib) mkMerge mkAfter getExe;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.colony) prefixes;

  # Pocket ID login source, client `gitea` (declared on `middleman`)
  oidcSource = "id.${pubDomain}";
in
{
  config = {
    fileSystems = {
      "/var/lib/gitea" = {
        device = "/dev/disk/by-label/git";
        fsType = "ext4";
      };
    };

    users = {
      users.git = {
        description = "Gitea Service";
        home = config.services.gitea.stateDir;
        useDefaultShell = true;
        group = config.services.gitea.group;
        isSystemUser = true;
      };
      groups.git = {};
    };

    systemd = {
      services = {
        gitea = mkMerge [
          (lib.my.systemdAwaitPostgres pkgs.postgresql "colony-psql")
          {
            preStart =
            let
              repSec = "${pkgs.replace-secret}/bin/replace-secret";
              confPath = "${config.services.gitea.customDir}/conf/app.ini";
            in
            ''
              gitea_extra_setup() {
                chmod u+w '${confPath}'
                ${repSec} '#miniosecret#' '${config.age.secrets."gitea/minio.txt".path}' '${confPath}'
                chmod u-w '${confPath}'
              }

              (umask 027; gitea_extra_setup)
            '';

            # Uploaded release assets are buffered through a temp file before being stored.
            # The default /tmp is on the small tmpfs root, so keep them on the state volume.
            environment.TMPDIR = "${config.services.gitea.stateDir}/tmp";
          }
          {
            # Gitea keeps login sources in its database: add the Pocket ID one, or bring it up to
            # date. The server only reads them at startup, so this runs before it; a failure only
            # warns, so Gitea still starts. The CLI only takes the secret as an argument.
            preStart = mkAfter (
            let
              gitea = getExe config.services.gitea.package;
            in
            ''
              oidc_source_setup() {
                local oidc_args=(
                  --name '${oidcSource}'
                  --provider openidConnect
                  --key gitea
                  --secret "$(< '${config.age.secrets."gitea/oidc-secret.txt".path}')"
                  --auto-discover-url 'https://${oidcSource}/.well-known/openid-configuration'
                  --scopes openid --scopes email --scopes profile
                )

                local list oidc_id
                list="$(${gitea} admin auth list)" || return
                oidc_id="$(${pkgs.gawk}/bin/awk '$2 == "${oidcSource}" { print $1 }' <<< "$list")" || return
                if [ -n "$oidc_id" ]; then
                  ${gitea} admin auth update-oauth --id "$oidc_id" "''${oidc_args[@]}"
                else
                  ${gitea} admin auth add-oauth "''${oidc_args[@]}"
                fi
              }

              if ! oidc_source_setup; then
                echo "Couldn't set up the ${oidcSource} login source; starting without it" >&2
              fi
            '');
          }
        ];
      };

      tmpfiles.settings."10-gitea-tmp"."${config.services.gitea.stateDir}/tmp".d = {
        user = config.services.gitea.user;
        group = config.services.gitea.group;
        mode = "0700";
      };
    };

    services = {
      gitea = {
        enable = true;
        user = "git";
        group = "git";
        appName = "/dev/player0 git";
        stateDir = "/var/lib/gitea";
        lfs.enable = true;
        database = {
          type = "postgres";
          createDatabase = false;
          host = "colony-psql";
          user = "gitea";
          passwordFile = config.age.secrets."gitea/db.txt".path;
        };
        mailerPasswordFile = config.age.secrets."gitea/mail.txt".path;
        settings = {
          server = {
            SSH_DOMAIN = "git.${pubDomain}";
            HTTP_ADDR = "::";
            ROOT_URL = "https://git.${pubDomain}/";
          };
          service = {
            DISABLE_REGISTRATION = true;
            ENABLE_NOTIFY_MAIL = true;
          };
          session = {
            COOKIE_SECURE = true;
          };
          repository = {
            DEFAULT_BRANCH = "master";
          };
          mailer = {
            ENABLED = true;
            PROTOCOL = "smtp+starttls";
            SMTP_ADDR = "mail.nul.ie";
            SMTP_PORT = 587;
            USER = "git@nul.ie";
            FROM = "Gitea <git@nul.ie>";
          };
          "email.incoming" = {
            ENABLED = true;
            HOST = "mail.nul.ie";
            PORT = 993;
            USE_TLS = true;
            USERNAME = "git@nul.ie";
            PASSWORD = "#mailerpass#";
            REPLY_TO_ADDRESS = "git+%{token}@nul.ie";
          };
          storage = {
            STORAGE_TYPE = "minio";
            SERVE_DIRECT = true;
            MINIO_ENDPOINT = "s3.${pubDomain}";
            MINIO_ACCESS_KEY_ID = "gitea";
            MINIO_SECRET_ACCESS_KEY = "#miniosecret#";
            MINIO_BUCKET = "gitea";
            MINIO_LOCATION = "eu-central-1";
            MINIO_USE_SSL = true;
          };
          actions = {
            ENABLED = true;
            # Match the runner's job timeout; the default (3h) fails long builds that are still running
            ENDLESS_TASK_TIMEOUT = "8h";
          };
        };
      };
    };

    my = {
      secrets = {
        files =
        let
          ownedByGit = {
            owner = "git";
            group = "git";
          };
        in
        {
          "gitea/db.txt" = ownedByGit;
          "gitea/mail.txt" = ownedByGit;
          "gitea/minio.txt" = ownedByGit;
          # Shared with `middleman`, which registers it with Pocket ID
          "gitea/oidc-secret.txt" = ownedByGit;
        };
      };
    };
  };
}
