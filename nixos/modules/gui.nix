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

    security = {
      polkit.enable = true;
      pam.services.swaylock = {};
    };

    environment.systemPackages = with pkgs; [
      # for pw-jack
      pipewire.jack
      swaylock
    ];
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

      udev = {
        extraRules = ''
          # Nvidia
          SUBSYSTEM=="usb", ATTR{idVendor}=="0955", MODE="0664", GROUP="wheel"
          # Nintendo
          SUBSYSTEM=="usb", ATTR{idVendor}=="057e", MODE="0664", GROUP="wheel"
        '';
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

    xdg = {
      portal = {
        enable = true;
        # For sway
        wlr.enable = true;
      };
    };
  };
}
