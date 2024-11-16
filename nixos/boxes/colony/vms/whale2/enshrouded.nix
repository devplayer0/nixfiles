{ lib, config, allAssignments, ... }:
let
  inherit (lib) concatStringsSep;
  inherit (lib.my) dockerNetAssignment;
in
{
  config = {
    virtualisation.oci-containers.containers = {
      enshrouded = {
        image = "sknnr/enshrouded-dedicated-server@sha256:f163e8ba9caa2115d8a0a7b16c3696968242fb6fba82706d9a77a882df083497";

        environment = {
          SERVER_NAME = "UWUshrouded";
          # SERVER_IP = "::"; # no IPv6?? :(
          TZ = "Europe/Dublin";
        };
        environmentFiles = [ config.age.secrets."whale2/enshrouded.env".path ];

        volumes = [
          "enshrouded:/home/steam/enshrouded/savegame"
        ];

        extraOptions = [
          ''--network=colony:${dockerNetAssignment allAssignments "enshrouded-oci"}''
        ];
      };
    };

    my = {
      secrets.files = {
        "whale2/enshrouded.env" = {};
      };
    };
  };
}
