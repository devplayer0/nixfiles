{ lib, options, config, ... }:
let
  inherit (lib) mkIf mkDefault mkOption mkAliasDefinitions;
  inherit (lib.my) mkBoolOpt' mkDefault';

  cfg = config.my.user;
  user' = cfg.config;
in
{
  options.my.user = with lib.types; {
    enable = mkBoolOpt' true "Whether to create a primary user.";
    config = mkOption {
      type = options.users.users.type.nestedTypes.elemType;
      default = { };
      description = "User definition (as `users.users.*`).";
    };
    homeConfig = mkOption {
      type = options.home-manager.users.type.nestedTypes.elemType;
      default = { };
      # Prevent docs traversing into all of home-manager
      visible = "shallow";
      description = "Home configuration (as `home-manager.users.*`)";
    };
  };

  config = mkIf cfg.enable {
    my = {
      user = {
        config = {
          name = mkDefault' "dev";
          isNormalUser = true;
          uid = mkDefault 1000;
          extraGroups = mkDefault [ "wheel" ];
          password = mkDefault "hunter2"; # TODO: secrets...
          shell =
            let shell = cfg.homeConfig.my.shell;
            in mkIf (shell != null) (mkDefault' shell);
          openssh.authorizedKeys.keyFiles = [ lib.my.authorizedKeys ];
        };
        # In order for this option to evaluate on its own, home-manager expects the `name` (which is derived from the
        # parent attr name) to be the users name, aka `home-manager.users.<name>`
        homeConfig = { _module.args.name = lib.mkForce user'.name; };
      };

      deploy.authorizedKeys = mkDefault user'.openssh.authorizedKeys;
    };

    # mkAliasDefinitions will copy the unmerged defintions to allow the upstream submodule to deal with
    users.users.${user'.name} = mkAliasDefinitions options.my.user.config;

    # NOTE: As the "outermost" module is still being evaluated in NixOS land, special params (e.g. pkgs) won't be
    # passed to it
    home-manager.users.${user'.name} = mkAliasDefinitions options.my.user.homeConfig;
  };
}
