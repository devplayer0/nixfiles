{ lib, config, allAssignments, ... }:
let
  inherit (lib) concatStringsSep;
  inherit (lib.my) dockerNetAssignment;

  # devplayer0
  op = "6d7d971b-ce10-435b-85c5-c99c0d8d288c";
in
{
  config = {
    virtualisation.oci-containers.containers = {
      simpcraft = {
        image = "ghcr.io/itzg/minecraft-server:2023.12.2-java17-alpine";

        environment = {
          TYPE = "MODRINTH";

          EULA = "true";
          ENABLE_QUERY = "true";
          MOTD = "§4§k----- §9S§ai§bm§cp§dc§er§fa§6f§5t §4§k-----";
          ICON = "/ext/icon.png";

          EXISTING_WHITELIST_FILE = "SYNCHRONIZE";
          WHITELIST = concatStringsSep "," [
            op
            "dcd2ecb9-2b5e-49cb-9d4f-f5a76162df56" # Elderlypug
            "fcb26db2-c3ce-41aa-b588-efec79d37a8a" # Jesthral_
            "1d366062-12c0-4e29-aba7-6ab5d8c6bb05" # shr3kas0ras
            "703b378a-09f9-4c1d-9876-1c9305728c49" # OROURKEIRE
            "f105bbe6-eda6-4a13-a8cf-894e77cab77b" # Adzerq
            "1fc94979-41fb-497a-81e9-34ae24ca537a" # johnnyscrims
            "d53c91df-b6e6-4463-b106-e8427d7a8d01" # BossLonus
            "f439f64d-91c9-4c74-9ce5-df4d24cd8e05" # hynge_
            "d6ec4c91-5da2-44eb-b89d-71dc8fe017a0" # Eefah98
          ];
          EXISTING_OPS_FILE = "SYNCHRONIZE";
          OPS = op;
          DIFFICULTY = "normal";
          SPAWN_PROTECTION = "0";
          VIEW_DISTANCE = "20";

          MAX_MEMORY = "6G";
          MODRINTH_MODPACK = "https://cdn.modrinth.com/data/CIYf3Hk8/versions/CN6MqSAU/Simpcraft-0.1.0.mrpack";

          TZ = "Europe/Dublin";
        };

        volumes = [
          "minecraft_data:/data"
          "${./icon.png}:/ext/icon.png:ro"
        ];

        extraOptions = [
          ''--network=colony:${dockerNetAssignment allAssignments "simpcraft-oci"}''
        ];
      };
    };
  };
}