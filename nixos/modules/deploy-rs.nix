{ lib, pkgs, config, systems, ... }:
let
  inherit (builtins) head attrNames;
  inherit (lib) mkMerge mkIf mkDefault optionalAttrs mapAttrs';
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.deploy;

  ctrProfiles = optionalAttrs cfg.generate.containers.enable (mapAttrs' (n: c:
  let
    ctrConfig = systems."${n}".configuration.config;
  in
  {
    name = "container-${n}";
    value = {
      path = pkgs.deploy-rs.lib.activate.custom ctrConfig.my.buildAs.container
        ''
          systemctl ${if c.hotReload then "reload" else "restart"} systemd-nspawn@${n}
        '';
      profilePath = "/nix/var/nix/profiles/per-container/${n}/system";

      user = "root";
    };
  }) config.my.containers.instances);
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
      containers.enable = mkBoolOpt' true "Whether to generate deploy-rs profiles for this system's containers.";
    };
  };

  config = mkMerge [
    {
      my.deploy.enable = mkIf config.my.build.isDevVM false;
    }
    (mkIf cfg.enable {
      my.deploy.node = {
        hostname = mkDefault config.networking.fqdn;
        profilesOrder = [ "system" ] ++ (attrNames ctrProfiles);
        profiles = {
          system = mkIf cfg.generate.system.enable {
            path = pkgs.deploy-rs.lib.activate.nixos { inherit config; };

            user = "root";
          };
        } // ctrProfiles;

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
