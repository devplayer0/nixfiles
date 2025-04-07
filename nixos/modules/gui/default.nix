{ lib, pkgs, config, ... }:
let
  inherit (lib) optional mkIf mkDefault mkMerge;
  inherit (lib.my) mkBoolOpt';

  cfg = config.my.gui;

  androidUdevRules = pkgs.runCommand "udev-rules-android" {
    rulesFile = ./android-udev.rules;
  } ''
    install -D "$rulesFile" "$out"/lib/udev/rules.d/51-android.rules
  '';
in
{
  options.my.gui = with lib.types; {
    enable = mkBoolOpt' true "Whether to enable GUI system options.";
  };

  config = mkIf cfg.enable {
    hardware = {
      graphics.enable = mkDefault true;
    };

    systemd = {
      tmpfiles.rules = [
        "d /tmp/screenshots 0777 root root"
      ];
    };

    security = {
      polkit.enable = true;
      pam.services.swaylock-plugin = {};
    };

    users = {
      groups = {
        adbusers.gid = lib.my.c.ids.gids.adbusers;
      };
    };

    environment.systemPackages = with pkgs; [
      # for pw-jack
      pipewire.jack
      swaylock-plugin
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
      udisks2.enable = true;

      udev = {
        packages = [
          androidUdevRules
        ];
        extraRules = ''
          # Nvidia
          SUBSYSTEM=="usb", ATTR{idVendor}=="0955", MODE="0664", GROUP="wheel"
          # Nintendo
          SUBSYSTEM=="usb", ATTR{idVendor}=="057e", MODE="0664", GROUP="wheel"
          # FT
          SUBSYSTEM=="usb", ATTR{idVendor}=="0403", MODE="0664", GROUP="wheel"
          # /dev/player0
          SUBSYSTEM=="usb", ATTR{idVendor}=="6969", MODE="0664", GROUP="wheel"
        '';
      };
    };

    programs.dconf.enable = true;

    fonts.packages = with pkgs; [
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
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
        ];
        # For sway
        wlr.enable = true;
        configPackages = [
          (pkgs.writeTextDir "share/xdg-desktop-portal/sway-portals.conf" ''
            [preferred]
            default=gtk
            org.freedesktop.impl.portal.Screenshot=wlr
            org.freedesktop.impl.portal.ScreenCast=wlr
          '')
        ];
      };
    };

    my = {
      user = {
        config = {
          extraGroups = [ "adbusers" ];
        };
      };
    };
  };
}
