{ lib, options, config, ... }:
let
  inherit (lib) mkIf mkDefault mkOption mkMerge mkAliasDefinitions optional;
  inherit (lib.my) mkBoolOpt' mkOpt' mkDefault';

  cfg = config.my.user;
  user' = cfg.config;
  user = config.users.users.${user'.name};
in
{
  options.my.user = with lib.types; {
    enable = mkBoolOpt' true "Whether to create a primary user.";
    passwordSecret = mkOpt' (nullOr str) "user-passwd.txt" "Name of user password secret.";
    tmphome = mkBoolOpt' true "Whether to persist home directory files under tmproot";
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

  config = mkIf cfg.enable (mkMerge [
    {
      my = {
        user = {
          config = {
            name = mkDefault' "dev";
            isNormalUser = true;
            uid = mkDefault 1000;
            extraGroups =
              [ "wheel" "kvm" "dialout" ] ++
              (optional config.networking.networkmanager.enable "networkmanager") ++
              (optional config.virtualisation.libvirtd.enable "libvirtd") ++
              (optional config.programs.wireshark.enable "wireshark") ++
              (with config.services.headscale; (optional enable group));
            password = mkIf (cfg.passwordSecret == null) (mkDefault "hunter2");
            shell =
              let shell = cfg.homeConfig.my.shell;
              in mkIf (shell != null) (mkDefault' shell);
            openssh.authorizedKeys.keyFiles = [ lib.my.c.sshKeyFiles.me ];
          };
          homeConfig = {
            # In order for this option to evaluate on its own, home-manager expects the `name` (which is derived from the
            # parent attr name) to be the users name, aka `home-manager.users.<name>`
            _module.args.name = lib.mkForce user'.name;
          };
        };
        tmproot = mkIf cfg.tmphome {
          unsaved.ignore = [
            # Auto-generated (on activation?)
            "/home/${user'.name}/.nix-profile"
            "/home/${user'.name}/.nix-defexpr"

            "/home/${user'.name}/.config/fish/fish_variables"
          ];
          persistence.config.users."${user'.name}" = {
            files = [
              ".bash_history"
              ".lesshst"
            ];
            directories = [
              # Persist all of fish; it's not easy to persist just the history fish won't let you move it to a different
              # directory. Also it does some funny stuff and can't really be a symlink it seems.
              ".local/share/fish"

              ".cache/nix"
            ];
          };
        };
      };

      # mkAliasDefinitions will copy the unmerged defintions to allow the upstream submodule to deal with
      users.users.${user'.name} = mkAliasDefinitions options.my.user.config;

      # NOTE: As the "outermost" module is still being evaluated in NixOS land, special params (e.g. pkgs) won't be
      # passed to it
      home-manager.users.${user'.name} = mkAliasDefinitions options.my.user.homeConfig;

      systemd.services.nixfiles-mutable.script = ''
        chown -R ${user'.name} /run/nixfiles
      '';
    }
    (mkIf (cfg.passwordSecret != null) {
      my = {
        secrets.files."${cfg.passwordSecret}" = {};
        user.config.hashedPasswordFile = config.age.secrets."${cfg.passwordSecret}".path;
      };
    })
  ]);
}
