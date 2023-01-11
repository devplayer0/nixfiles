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
        # TODO: get working again
        hercules-ci-agent.enable = false;
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

        nix-cache-gc =
        let
          configFile = pkgs.writeText "nix-cache-gc.ini" ''
            [gc]
            threshold = 256000
            stop = 204800

            [s3]
            endpoint = s3.nul.ie
            bucket = nix-cache
            access_key = nix-gc
          '';
        in
        {
          description = "Nix cache garbage collection";
          path = [ (pkgs.python310.withPackages (ps: with ps; [ minio ])) ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = [ ''${./nix_cache_gc.py} -c ${configFile} -c ${config.age.secrets."nix-cache-gc.ini".path}'' ];
          };
        };
      };
      timers = {
        nix-cache-gc = {
          description = "Nix cache garbage collection timer";
          wantedBy = [ "timers.target" ];
          timerConfig.OnCalendar = "hourly";
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
          "nix-cache-gc.ini" = {};
        };
      };
    };
  };
}
