{
  nixos.systems.vaultwarden = {
    system = "x86_64-linux";
    nixpkgs = "unstable";

    configuration = { lib, config, ... }:
    let
      inherit (lib) mkMerge mkIf mkForce;

      vwData = "/var/lib/vaultwarden";
      vwSecrets = "vaultwarden.env";
    in
    {
      config = mkMerge [
        {
          my = {
            server.enable = true;

            secrets = {
              files."${vwSecrets}" = {};
            };

            firewall = {
              tcp.allowed = [ 80 3012 ];
            };
          };

          systemd.services.vaultwarden.serviceConfig.StateDirectory = mkForce "vaultwarden";
          services = {
            vaultwarden = {
              enable = true;
              config = {
                dataFolder = vwData;
                webVaultEnabled = true;

                rocketPort = 80;
                websocketEnabled = true;
                websocketPort = 3012;
              };
              environmentFile = config.age.secrets."${vwSecrets}".path;
            };
          };
        }
        (mkIf config.my.build.isDevVM {
          my.tmproot.persistence.config.directories = [
            {
              directory = vwData;
              user = config.users.users.vaultwarden.name;
              group = config.users.groups.vaultwarden.name;
            }
          ];
          virtualisation = {
            forwardPorts = [
              { from = "host"; host.port = 8080; guest.port = 80; }
            ];
          };
        })
      ];
    };
  };
}
