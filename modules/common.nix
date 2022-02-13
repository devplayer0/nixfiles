{ lib, pkgs, inputs, homeModules, config, options, ... }:
let
  inherit (builtins) attrValues;
  inherit (lib) mkIf mkDefault mkAliasDefinitions;
  inherit (lib.my) mkOpt';
in
{
  options.my = with lib.types; {
    # Pretty hacky but too lazy to figure out if there's a better way to alias the options
    user = mkOpt' (attrsOf anything) { } "User definition (as `users.users.*`).";
    homeConfig = mkOpt' anything {} "Home configuration (as `home-manager.users.*`)";
  };

  config =
    let
      defaultUsername = "dev";
      uname = config.my.user.name;
    in
    {
      my = {
        user = {
          name = mkDefault defaultUsername;
          isNormalUser = true;
          uid = mkDefault 1000;
          extraGroups = mkDefault [ "wheel" ];
          password = mkDefault "hunter2"; # TODO: secrets...
        };
      };

      home-manager = {
        useGlobalPkgs = mkDefault true;
        useUserPackages = mkDefault true;
        sharedModules = homeModules ++ [{
          _module.args = { inherit inputs; isStandalone = false; };
        }];
      };

      users = {
        mutableUsers = false;
        users.${uname} = mkAliasDefinitions options.my.user;
      };

      # NOTE: As the "outermost" module is still being evaluated in NixOS land, special params (e.g. pkgs) won't be
      # passed to it
      home-manager.users.${uname} = config.my.homeConfig;

      security = {
        sudo.enable = mkDefault false;
        doas = {
          enable = mkDefault true;
          wheelNeedsPassword = mkDefault false;
        };
      };

      nix = {
        extraOptions =
          ''
            experimental-features = nix-command flakes ca-derivations
          '';
      };
      nixpkgs = {
        overlays = [
          inputs.nix.overlay
        ];
        config = {
          allowUnfree = true;
        };
      };

      time.timeZone = mkDefault "Europe/Dublin";

      boot = {
        # Use latest LTS release by default
        kernelPackages = mkDefault pkgs.linuxKernel.packages.linux_5_15;
        loader = {
          efi = {
            efiSysMountPoint = mkDefault "/boot";
            canTouchEfiVariables = mkDefault false;
          };
          systemd-boot = {
            enable = mkDefault true;
            editor = mkDefault true;
            consoleMode = mkDefault "max";
            configurationLimit = mkDefault 10;
            memtest86.enable = mkDefault true;
          };
        };
      };

      networking = {
        useDHCP = mkDefault false;
        enableIPv6 = mkDefault true;
      };

      environment.systemPackages = with pkgs; [
        bash-completion
        vim
      ];

      services.openssh = {
        enable = true;
      };

      system = {
        stateVersion = "21.11";
        configurationRevision = with inputs; mkIf (self ? rev) self.rev;
      };
    };
}
