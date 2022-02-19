{ lib, extendModules, pkgs, options, config, baseModules, ... }:
let
  inherit (builtins) head;
  inherit (lib) mkOption mkMerge mkIf mkDefault;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.deploy;
in
{
  options.my.deploy = with lib.types; rec {
    authorizedKeys = {
      keys = mkOpt' (listOf singleLineStr) [ ] "SSH public keys to add to the default deployment user.";
      keyFiles = mkOpt' (listOf str) [ ] "SSH public key files to add to the default deployment user.";
    };

    enable = mkBoolOpt' true "Whether to expose deploy-rs configuration for this system.";
    node = mkOpt' lib.my.deploy-rs.node { } "deploy-rs node configuration.";

    generate = {
      system.enable = mkBoolOpt' true "Whether to generate a deploy-rs profile for this system's config.";
    };
    rendered = mkOption {
      type = nullOr (attrsOf anything);
      default = null;
      internal = true;
      description = "Rendered deploy-rs node configuration.";
    };
  };

  config = mkMerge [
    {
      my.deploy = {
        enable = mkIf config.my.build.isDevVM false;

        node = {
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
        rendered = mkIf cfg.enable (lib.my.deploy-rs.filterOpts cfg.node);
      };
    }
    (mkIf cfg.enable {
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
