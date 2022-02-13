{ lib, pkgs, inputs, isStandalone, config, ... }:
let
  inherit (lib) mkMerge mkIf mkDefault mkForce;
in
mkMerge [
  {
    programs = {
      home-manager = {
        # Even when enabled this will only be actually installed in standalone mode
        enable = true;
      };

      htop = {
        enable = true;
        settings = {};
      };
    };

    home = {
      language.base = mkDefault "en_IE.UTF-8";

      packages = with pkgs; [
        tree
        iperf3
      ];

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

    home = {
      packages = with pkgs; [
        nix
      ];
    };
  })
]
