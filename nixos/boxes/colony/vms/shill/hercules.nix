{ lib, pkgs, config, ... }: {
  config = {
    system = {
      activationScripts.herculesAWSCredsRoot.text = ''
        mkdir -p /root/.aws
        ln -sf "${config.age.secrets."hercules/aws-credentials.ini".path}" /root/.aws/credentials
      '';
    };

    systemd = {
      services = {
        hercules-ci-agent-pre =
        let
          deps = [ "hercules-ci-agent.service" ];
          awsCredsPath = "${config.services.hercules-ci-agent.settings.baseDirectory}/.aws/credentials";
        in
        {
          before = deps;
          requiredBy = deps;
          serviceConfig = {
            Type = "oneshot";
            User = "hercules-ci-agent";
          };
          script = ''
            mkdir -p "$(dirname "${awsCredsPath}")"
            ln -sf "${config.age.secrets."hercules/aws-credentials.ini".path}" "${awsCredsPath}"
          '';
        };
      };
    };

    services = {
      hercules-ci-agent = {
        enable = true;
        settings = {
          concurrentTasks = 20;
          clusterJoinTokenPath = config.age.secrets."hercules/cluster-join-token.key".path;
          binaryCachesPath = config.age.secrets."hercules/binary-caches.json".path;
        };
      };
    };

    my = {
      secrets = {
        files =
        let
          ownedByAgent = {
            owner = "hercules-ci-agent";
            group = "hercules-ci-agent";
          };
        in
        {
          "hercules/cluster-join-token.key" = ownedByAgent;
          "hercules/binary-caches.json" = ownedByAgent;
          "hercules/aws-credentials.ini" = ownedByAgent;
        };
      };
    };
  };
}
