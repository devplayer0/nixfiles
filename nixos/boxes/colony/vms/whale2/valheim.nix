{ lib, config, allAssignments, ... }:
let
  inherit (lib.my) dockerNetAssignment;
in
{
  config = {
    virtualisation.oci-containers.containers = {
      valheim = {
        image = "lloesche/valheim-server@sha256:8d910b15e3ab645a31c85799338d3dc043cabe891a34b43cbd574a1453837205";

        environment = {
          SERVER_NAME = "amogus sus";
          SERVER_PUBLIC = "true";
          WORLD_NAME = "simpland2";
          ADMINLIST_IDS = "76561198049818986";
          TZ = "Europe/Dublin";
        };
        environmentFiles = [ config.age.secrets."whale2/valheim.env".path ];

        volumes = [
          "data:/config"
          "server:/opt/valheim"
        ];

        extraOptions = [
          ''--network=colony:${dockerNetAssignment allAssignments "valheim-oci"}''
          "--cap-add=SYS_NICE"
        ];
      };
    };

    my = {
      secrets.files = {
        "whale2/valheim.env" = {};
      };
    };
  };
}
