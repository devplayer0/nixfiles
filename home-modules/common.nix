{ lib, pkgs, inputs, isStandalone, config, ... }:
let
  inherit (lib) mkMerge mkIf mkDefault mkForce;
in
mkMerge [
  {
    nix.registry = {
      pkgs = {
        to = {
          type = "path";
          path = toString pkgs.path;
        };
        exact = true;
      };
    };

    programs = {
      # Even when enabled this will only be actually installed in standalone mode
      # Note: `home-manager.path` is for telling home-manager is installed and setting it in NIX_PATH, which we should
      # never care about.
      home-manager.enable = true;

      bash = {
        # This not only installs bash but has home-manager control .bashrc and friends
        enable = mkDefault true;
      };

      direnv = {
        enable = mkDefault true;
        nix-direnv.enable = true;
      };

      htop = {
        enable = true;
        settings = {};
      };
    };

    home = {
      packages = with pkgs; [
        tree
        iperf3
      ];

      sessionVariables = {
        EDITOR = "vim";
      };

      language.base = mkDefault "en_IE.UTF-8";

      # The flake passes a default setting, but we don't care about that
      stateVersion = mkForce "22.05";
    };
  }
  (mkIf isStandalone {
    # Note: this only applies outside NixOS where home-manager imports nixpkgs internally
    nixpkgs = {
      overlays = [
        inputs.nix.overlay
      ];
      config = {
        allowUnfree = true;
      };
    };

    fonts.fontconfig.enable = true;

    home = {
      packages = with pkgs; [
        nix
      ];
    };
  })
]
