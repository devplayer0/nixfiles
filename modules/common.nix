{ lib, pkgs, inputs, system, config, options, ... }:
let
  inherit (lib) mkIf mkDefault mkAliasDefinitions;
  inherit (lib.my) mkOpt;
in
{
  options.my = with lib.types; {
    user = mkOpt (attrsOf anything) { };
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

      time.timeZone = mkDefault "Europe/Dublin";

      users = {
        mutableUsers = false;
        users.${uname} = mkAliasDefinitions options.my.user;
      };

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
      nixpkgs = {
        config = {
          allowUnfree = true;
        };
      };

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
        tree
        vim
        htop
        iperf3
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
