{ lib, pkgs, config, ... }:
let
  inherit (builtins) toJSON;
  inherit (lib) mkForce;
  inherit (lib.my.c) pubDomain;

  cfgFile = pkgs.writeText "gitea-actions-runner.yaml" (toJSON {
    container = {
      network = "colony";
    };
  });
in
{
  config = {
    services = {
      gitea-actions-runner.instances = {
        main = {
          enable = true;
          name = "main-docker";
          labels = [ ];
          url = "https://git.${pubDomain}";
          tokenFile = config.age.secrets."gitea/actions-runner.env".path;
        };
      };
    };

    users = with lib.my.c.ids; {
      users = {
        gitea-runner = {
          isSystemUser = true;
          uid = uids.gitea-runner;
          group = "gitea-runner";
          home = "/var/lib/gitea-runner";
        };
      };
      groups = {
        gitea-runner.gid = gids.gitea-runner;
      };
    };

    systemd = {
      services = {
        gitea-runner-main.serviceConfig = {
          # Needs to be able to read its secrets
          DynamicUser = mkForce false;
          User = "gitea-runner";
          Group = "gitea-runner";
          ExecStart = mkForce "${config.services.gitea-actions-runner.package}/bin/act_runner -c ${cfgFile} daemon";
        };
      };
    };

    my = {
      secrets.files = {
        "gitea/actions-runner.env" = {
          owner = "gitea-runner";
          group = "gitea-runner";
        };
      };
    };
  };
}