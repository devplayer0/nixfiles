{ lib, pkgs, config, allAssignments, ... }:
let
  inherit (lib) concatStringsSep;
  inherit (lib.my) dockerNetAssignment;

  # devplayer0
  op = "6d7d971b-ce10-435b-85c5-c99c0d8d288c";
  kev = "703b378a-09f9-4c1d-9876-1c9305728c49";
  whitelist = concatStringsSep "," [
    op
    "dcd2ecb9-2b5e-49cb-9d4f-f5a76162df56" # Elderlypug
    "fcb26db2-c3ce-41aa-b588-efec79d37a8a" # Jesthral_
    "1d366062-12c0-4e29-aba7-6ab5d8c6bb05" # shr3kas0ras
    kev
    "f105bbe6-eda6-4a13-a8cf-894e77cab77b" # Adzerq
    "1fc94979-41fb-497a-81e9-34ae24ca537a" # johnnyscrims
    "d53c91df-b6e6-4463-b106-e8427d7a8d01" # BossLonus
    "f439f64d-91c9-4c74-9ce5-df4d24cd8e05" # hynge_
    "d6ec4c91-5da2-44eb-b89d-71dc8fe017a0" # Eefah98
    "096a7348-fabe-4b2d-93fc-fd1fd5608fb0" # ToTheMoonStar
  ];

  fastback = {
    gitConfig = pkgs.writeText "git-config" ''
      [user]
      	email = "simpcraft@nul.ie"
      	name = "Simpcraft bot"
    '';
  };
in
{
  config = {
    virtualisation.oci-containers.containers = {
      simpcraft = {
        image = "git.nul.ie/dev/craftblock:2024.1.0-java17-alpine";

        environment = {
          TYPE = "MODRINTH";

          EULA = "true";
          ENABLE_QUERY = "true";
          ENABLE_RCON = "true";
          MOTD = "§4§k----- §9S§ai§bm§cp§dc§er§fa§6f§5t §4§k-----";
          ICON = "/ext/icon.png";

          EXISTING_WHITELIST_FILE = "SYNCHRONIZE";
          WHITELIST = whitelist;
          EXISTING_OPS_FILE = "SYNCHRONIZE";
          OPS = op;
          DIFFICULTY = "normal";
          SPAWN_PROTECTION = "0";
          VIEW_DISTANCE = "20";

          MAX_MEMORY = "8G";
          MODRINTH_MODPACK = "https://cdn.modrinth.com/data/CIYf3Hk8/versions/NGutsQSd/Simpcraft-0.2.1.mrpack";

          TZ = "Europe/Dublin";
        };
        environmentFiles = [ config.age.secrets."whale2/simpcraft.env".path ];

        volumes = [
          "minecraft_data:/data"
          "${./icon.png}:/ext/icon.png:ro"
          "${fastback.gitConfig}:/data/.config/git/config:ro"
        ];

        extraOptions = [
          ''--network=colony:${dockerNetAssignment allAssignments "simpcraft-oci"}''
        ];
      };

      # simpcraft-staging = {
      #   image = "git.nul.ie/dev/craftblock:2024.1.0-java17-alpine";

      #   environment = {
      #     TYPE = "MODRINTH";

      #     EULA = "true";
      #     ENABLE_QUERY = "true";
      #     ENABLE_RCON = "true";
      #     MOTD = "§4§k----- §9S§ai§bm§cp§dc§er§fa§6f§5t [staging] §4§k-----";
      #     ICON = "/ext/icon.png";

      #     EXISTING_WHITELIST_FILE = "SYNCHRONIZE";
      #     WHITELIST = whitelist;
      #     EXISTING_OPS_FILE = "SYNCHRONIZE";
      #     OPS = op;
      #     DIFFICULTY = "normal";
      #     SPAWN_PROTECTION = "0";
      #     VIEW_DISTANCE = "20";

      #     MAX_MEMORY = "4G";
      #     MODRINTH_MODPACK = "https://cdn.modrinth.com/data/CIYf3Hk8/versions/Ym3sIi6H/Simpcraft-0.2.0.mrpack";

      #     TZ = "Europe/Dublin";
      #   };
      #   environmentFiles = [ config.age.secrets."whale2/simpcraft.env".path ];

      #   volumes = [
      #     "minecraft_staging_data:/data"
      #     "${./icon.png}:/ext/icon.png:ro"
      #   ];

      #   extraOptions = [
      #     ''--network=colony:${dockerNetAssignment allAssignments "simpcraft-staging-oci"}''
      #   ];
      # };

      kevcraft = {
        # 2025.2.1-java21-alpine
        image = "itzg/minecraft-server@sha256:57e319c15e9fee63f61029a65a33acc3de85118b21a2b4bb29f351cf4a915027";

        environment = {
          TYPE = "VANILLA";
          VERSION = "1.20.1";
          SERVER_PORT = "25567";
          QUERY_PORT = "25567";

          EULA = "true";
          ENABLE_QUERY = "true";
          ENABLE_RCON = "true";
          MOTD = "§4§k----- §9K§ae§bv§cc§dr§ea§ff§6t §4§k-----";
          ICON = "/ext/icon.png";

          EXISTING_WHITELIST_FILE = "SYNCHRONIZE";
          WHITELIST = whitelist;
          EXISTING_OPS_FILE = "SYNCHRONIZE";
          OPS = concatStringsSep "," [ op kev ];
          DIFFICULTY = "normal";
          SPAWN_PROTECTION = "0";
          # VIEW_DISTANCE = "20";

          MAX_MEMORY = "4G";

          TZ = "Europe/Dublin";
        };
        environmentFiles = [ config.age.secrets."whale2/simpcraft.env".path ];

        volumes = [
          "kevcraft_data:/data"
          "${./kev.png}:/ext/icon.png:ro"
        ];

        extraOptions = [
          ''--network=colony:${dockerNetAssignment allAssignments "kevcraft-oci"}''
        ];
      };

      kinkcraft = {
        # 2025.5.1-java21-alpine
        image = "itzg/minecraft-server@sha256:de26c7128e3935f3be48fd30283f0b5a6da1b3d9f1a10c9f92502ee1ba072f7b";

        environment = {
          TYPE = "MODRINTH";
          SERVER_PORT = "25568";
          QUERY_PORT = "25568";

          EULA = "true";
          ENABLE_QUERY = "true";
          ENABLE_RCON = "true";
          MOTD = "§4§k----- §9K§ai§bn§ck§dc§er§fa§6f§5t §4§k-----";
          ICON = "/ext/icon.png";

          EXISTING_WHITELIST_FILE = "SYNCHRONIZE";
          WHITELIST = whitelist;
          EXISTING_OPS_FILE = "SYNCHRONIZE";
          OPS = op;
          DIFFICULTY = "normal";
          SPAWN_PROTECTION = "0";
          VIEW_DISTANCE = "20";

          MAX_MEMORY = "6G";
          MODRINTH_MODPACK = "https://cdn.modrinth.com/data/CIYf3Hk8/versions/NGutsQSd/Simpcraft-0.2.1.mrpack";

          TZ = "Europe/Dublin";
        };
        environmentFiles = [ config.age.secrets."whale2/simpcraft.env".path ];

        volumes = [
          "kinkcraft_data:/data"
          "${./icon.png}:/ext/icon.png:ro"
        ];

        extraOptions = [
          ''--network=colony:${dockerNetAssignment allAssignments "kinkcraft-oci"}''
        ];
      };

    };

    services = {
      borgbackup.jobs.simpcraft =
      let
        rconCommand = cmd: ''${pkgs.mcrcon}/bin/mcrcon -H simpcraft-oci -p "$RCON_PASSWORD" "${cmd}"'';
      in
      {
        paths = [ "/var/lib/containers/storage/volumes/minecraft_data/_data/world" ];
        repo = "/var/lib/containers/backup/simpcraft";
        doInit = true;
        encryption.mode = "none";
        compression = "zstd,10";
        # every ~15 minutes offset from 5 minute intervals (Minecraft seems to save at precise times?)
        startAt = "*:03,17,33,47";
        prune.keep = {
          within = "12H";
          hourly = 48;
        };
        readWritePaths = [ "/var/lib/borgbackup" "/var/cache/borgbackup" ];

        # Avoid Minecraft poking the files while we back up
        preHook = rconCommand "save-off";
        postHook = rconCommand "save-on";
      };
    };

    systemd = {
      services = {
        borgbackup-job-simpcraft.serviceConfig.EnvironmentFile = [ config.age.secrets."whale2/simpcraft.env".path ];
      };
    };

    my = {
      secrets.files = {
        "whale2/simpcraft.env" = {};
      };
    };
  };
}
