{ lib, pkgs, inputs, system, config, options, ... }:
  let
    inherit (lib) mkIf mkDefault mkAliasDefinitions;
    inherit (lib.my) mkOpt;
  in {
    options.my = with lib.types; {
      user = mkOpt (attrsOf anything) {};
    };

    config =
      let
        defaultUsername = "dev";
        uname = config.my.user.name;
      in {
        my.user = rec {
          name = mkDefault defaultUsername;
          isNormalUser = true;
          uid = mkDefault 1000;
          extraGroups = mkDefault [ "wheel" ];
          password = mkDefault "hunter2"; # TODO: secrets...
        };

        time.timeZone = mkDefault "Europe/Dublin";

        users.mutableUsers = false;
        users.users.${uname} = mkAliasDefinitions options.my.user;
        users.groups.${uname}.gid = mkDefault config.users.users.${uname}.uid;

        security = {
          sudo.enable = mkDefault false;
          doas = {
            enable = mkDefault true;
            wheelNeedsPassword = mkDefault false;
          };
        };

        nix = {
          package = inputs.nix.defaultPackage.${system};
          extraOptions =
            ''
              experimental-features = nix-command flakes ca-derivations
            '';
        };

        environment.systemPackages = with pkgs; [
          vim
          iperf3
        ];

        system.stateVersion = "21.11";
        system.configurationRevision = with inputs; mkIf (self ? rev) self.rev;
      };
  }
