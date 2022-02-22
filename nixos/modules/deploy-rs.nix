{ lib, pkgs, config, ... }:
let
  inherit (builtins) head;
  inherit (lib) mkMerge mkIf mkDefault;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.deploy;
in
{
  options.my.deploy = with lib.types; {
    authorizedKeys = {
      keys = mkOpt' (listOf singleLineStr) [ ] "SSH public keys to add to the default deployment user.";
      keyFiles = mkOpt' (listOf path) [ lib.my.sshKeyFiles.deploy ] "SSH public key files to add to the default deployment user.";
    };

    enable = mkBoolOpt' true "Whether to expose deploy-rs configuration for this system.";
    inherit (lib.my.deploy-rs) node;

    generate = {
      system.enable = mkBoolOpt' true "Whether to generate a deploy-rs profile for this system's config.";
    };
  };

  config = mkMerge [
    {
      my.deploy.enable = mkIf config.my.build.isDevVM false;
    }
    (mkIf cfg.enable {
      my.deploy.node = {
        hostname = mkDefault config.networking.fqdn;
        profiles = {
          system = mkIf cfg.generate.system.enable {
            path = pkgs.deploy-rs.lib.activate.nixos { inherit config; };

            user = "root";
          };
        };

        sshUser = "deploy";
        user = mkDefault "root";
        sudo = mkDefault (if config.security.doas.enable then "doas -u" else "sudo -u");
        sshOpts = mkDefault [ "-p" (toString (head config.services.openssh.ports)) ];
      };

      users = {
        users."${cfg.node.sshUser}" = {
          isSystemUser = true;
          group = cfg.node.sshUser;
          extraGroups = mkDefault [ "wheel" ];
          shell = pkgs.bash;
          openssh.authorizedKeys = cfg.authorizedKeys;
        };
        groups."${cfg.node.sshUser}" = {};
      };
    })
  ];
}
