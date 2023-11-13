{ lib, pkgs, config, ... }:
let
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.colony) prefixes;
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
            DOMAIN = "git.${pubDomain}";
            HTTP_ADDR = "::";
            ROOT_URL = "https://git.${pubDomain}";
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
        };
      };

      firewall.extraRules = ''
        table inet filter {
          chain input {
            ip saddr ${prefixes.all.v4} tcp dport 3000 accept
            ip6 saddr ${prefixes.all.v6} tcp dport 3000 accept
          }
        }
      '';
    };
  };
}
