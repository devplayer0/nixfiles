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

    systemd = {
      tmpfiles.rules = [
        "d /tmp/screenshots 0777 root root"
      ];
    };

    security.polkit.enable = true;

    services = {
      pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
        jack.enable = true;
      };
      dbus = {
        packages = with pkgs; [ gcr ];
      };
      gnome = {
        gnome-keyring.enable = true;
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

    nixpkgs.overlays = [
      (self: super: {
        xdg-desktop-portal = super.xdg-desktop-portal.overrideAttrs (old: rec {
          # https://github.com/flatpak/xdg-desktop-portal/issues/861
          version = "1.14.6";

          src = pkgs.fetchFromGitHub {
            owner = "flatpak";
            repo = old.pname;
            rev = version;
            sha256 = "sha256-MD1zjKDWwvVTui0nYPgvVjX48DaHWcP7Q10vDrNKYz0=";
          };
        });
      })
    ];
    xdg = {
      portal = {
        enable = true;
        # For sway
        wlr.enable = true;
      };
    };
  };
}
