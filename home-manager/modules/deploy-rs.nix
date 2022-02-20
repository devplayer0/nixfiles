{ lib, pkgs, config, ... }:
let
  inherit (builtins) head;
  inherit (lib) mkMerge mkIf mkDefault;
  inherit (lib.my) mkBoolOpt';

  cfg = config.my.deploy;
in
{
  options.my.deploy = with lib.types; {
    enable = mkBoolOpt' true "Whether to expose deploy-rs configuration for this home configuration.";
    inherit (lib.my.deploy-rs) node;

    generate = {
      home.enable = mkBoolOpt' true "Whether to generate a deploy-rs profile for this home config.";
    };
  };

  config = mkMerge [
    {
      my.deploy.enable = mkIf (!config.my.isStandalone) false;
    }
    (mkIf cfg.enable {
      my.deploy.node = {
        profiles = {
          home = mkIf cfg.generate.home.enable {
            path = pkgs.deploy-rs.lib.activate.home-manager { inherit (config.home) activationPackage; };
            profilePath = "/nix/var/nix/profiles/per-user/${config.home.username}/profile";
          };
        };

        sshUser = mkDefault config.home.username;
        user = config.home.username;
        sudo = mkDefault "sudo -u";
      };
    })
  ];
}
