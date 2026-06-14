{ lib, pkgs, config, ... }:
let
  inherit (lib) mkForce;
  inherit (lib.my.c) pubDomain;
in
{
  config = {
    fileSystems = {
      "/var/cache/gitea-runner" = {
        device = "/dev/disk/by-label/actions-cache";
        fsType = "ext4";
      };
    };

    services = {
      gitea-actions-runner.instances = {
        main = {
          enable = true;
          name = "main-docker";
          labels = [
            "debian-node-trixie:docker://node:24-trixie"
            "ubuntu-26.04:docker://git.nul.ie/dev/actions-ubuntu:26.04"
          ];
          url = "https://git.${pubDomain}";
          tokenFile = config.age.secrets."gitea/actions-runner.env".path;
          settings = {
            runner = {
              timeout = "8h";
            };
            container = {
              network = "podman";
              privileged = true;
            };
            cache = {
              enabled = true;
              dir = "/var/cache/gitea-runner";
            };
          };
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
          CacheDirectory = "gitea-runner";
          DynamicUser = mkForce false;
          User = "gitea-runner";
          Group = "gitea-runner";
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
