{ lib, config, allAssignments, ... }:
let
  inherit (lib) concatStringsSep;
  inherit (lib.my) dockerNetAssignment;
in
{
  config = {
    virtualisation.oci-containers.containers = {
      valheim = {
        image = "ghcr.io/lloesche/valheim-server@sha256:d977ccbeff02d2509646fb0157b5e353ebadb3105a3ed351b9c309a09a61701b";

        environment = {
          BACKUPS_IF_IDLE = "false";
          SERVER_NAME = "amogus sus";
          SERVER_PUBLIC = "true";
          WORLD_NAME = "simpland2";
          ADMINLIST_IDS = "76561198049818986";
          PERMITTEDLIST_IDS = concatStringsSep " " [
            "76561198049818986" # /dev/player0
            "76561198044432445" # Nuda
            "76561198121606266" # El Pugador
            "76561198059894566" # hynge
          ];
          TZ = "Europe/Dublin";
        };
        environmentFiles = [ config.age.secrets."whale2/valheim.env".path ];

        volumes = [
          "valheim_data:/config"
          "valhem_server:/opt/valheim"
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
