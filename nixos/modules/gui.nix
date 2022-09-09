{ lib, pkgs, config, ... }:
let
  inherit (lib) optional mkIf mkDefault mkMerge;
  inherit (lib.my) mkBoolOpt';

  cfg = config.my.gui;
in
{
  options.my.gui = with lib.types; {
    enable = mkBoolOpt' true "Whether to enable GUI system options.";
  };

  config = mkIf cfg.enable {
    hardware = {
      opengl.enable = mkDefault true;
    };

    services = {
      pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
        jack.enable = true;
      };
    };

    programs.dconf.enable = true;

    fonts.fonts = with pkgs; [
      dejavu_fonts
      freefont_ttf
      gyre-fonts # TrueType substitutes for standard PostScript fonts
      liberation_ttf
      unifont
      noto-fonts-emoji
    ];
  };
}
