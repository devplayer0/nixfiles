{ lib, config, allAssignments, ... }:
let
  inherit (lib) concatStringsSep;
  inherit (lib.my) dockerNetAssignment;

  admin = "76561198049818986"; # /dev/player0
in
{
  config = {
    virtualisation.oci-containers.containers = {
      valheim = {
        image = "ghcr.io/community-valheim-tools/valheim-server@sha256:f3ccde9a4e292663cf5096d502ff33cc9617015f6d70b6a9ca0968543f165ef2";

        environment = {
          BACKUPS_IF_IDLE = "false";
          SERVER_NAME = "amogus sus";
          SERVER_PUBLIC = "true";
          # Previous world: simpland2
          WORLD_NAME = "simpland3";
          ADMINLIST_IDS = admin;
          PERMITTEDLIST_IDS = concatStringsSep " " [
            admin
            "76561198044432445" # Nuda
            "76561198121606266" # El Pugador
            "76561198059894566" # hynge
          ];
          TZ = "Europe/Dublin";
        };
        environmentFiles = [ config.age.secrets."whale2/valheim.env".path ];

        volumes = [
          "valheim_data:/config"
          "valheim_server:/opt/valheim"
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
