{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf mkDefault mkMerge mkForce;
  inherit (lib.my) mkBoolOpt';

  cfg = config.my.gui;
in
{
  options.my.gui = {
    enable = mkBoolOpt' true "Enable settings and packages meant for graphical systems";
    standalone = mkBoolOpt' false "Enable settings for fully Nix managed systems";
  };

  config = mkIf cfg.enable (mkMerge [
      {
        home = {
          packages = with pkgs; [
            (nerdfonts.override {
              fonts = [ "DroidSansMono" "SourceCodePro" ];
            })
            pavucontrol
          ];
        };

        programs = {
          alacritty = {
            enable = true;
            settings = {
              font.normal.family = "SauceCodePro Nerd Font Mono";
            };
          };
        };
      }
      (mkIf cfg.standalone {
        xdg = {
          userDirs = {
            enable = true;
            createDirectories = true;
            desktop = "$HOME/desktop";
            documents = "$HOME/documents";
            download = "$HOME/downloads";
            music = "$HOME/music";
            pictures = "$HOME/pictures";
            publicShare = "$HOME/public";
            templates = "$HOME/templates";
            videos = "$HOME/videos";
          };
        };

        home = {
          pointerCursor = {
            package = pkgs.vanilla-dmz;
            name = "Vanilla-DMZ";
            gtk.enable = true;
          };
        };

        fonts.fontconfig.enable = true;

        wayland = {
          windowManager = {
            sway = {
              enable = true;
              xwayland = true;
              config = {
                input = {
                  "type:touchpad" = {
                    tap = "enabled";
                    natural_scroll = "enable";
                  };
                };
                output = {
                  "*".bg = "${./stop-nixos.png} stretch";
                };

                modifier = "Mod4";
                terminal = "alacritty";
                keybindings =
                  let
                    cfg = config.wayland.windowManager.sway.config;
                    mod = cfg.modifier;
                  in
                  lib.mkOptionDefault {
                    "${mod}+d" = null;
                    "${mod}+x" = "exec ${cfg.menu}";
                    "${mod}+q" = "kill";
                    "${mod}+Shift+q" = "exec swaynag -t warning -m 'bruh you really wanna kill sway?' -b 'ye' 'swaymsg exit'";
                  };

                menu = "rofi -show run";
                bars = mkForce [ ];
              };

              swaynag = {
                enable = true;
              };
            };
          };
        };

        programs = {
          git = {
            enable = true;
            diff-so-fancy.enable = true;
            userEmail = "jackos1998@gmail.com";
            userName = "Jack O'Sullivan";
          };

          waybar = import ./waybar.nix { inherit lib pkgs config; };
          rofi = {
            enable = true;
            font = "SauceCodePro Nerd Font Mono";
            plugins = with pkgs; [
              rofi-calc
              rofi-emoji
            ];
            extraConfig = {
              modes = "window,run,ssh,filebrowser,calc,emoji";
            };
          };

          chromium = {
            enable = true;
            package = (pkgs.chromium.override { enableWideVine = true; }).overrideAttrs (old: {
              buildCommand = ''
                ${old.buildCommand}

                # Re-activate Google sync
                wrapProgram "$out"/bin/chromium \
                  --set NIXOS_OZONE_WL 1 \
                  --set GOOGLE_DEFAULT_CLIENT_ID "77185425430.apps.googleusercontent.com" \
                  --set GOOGLE_DEFAULT_CLIENT_SECRET "OTJgUOQcT7lO7GsGZq2G4IlT"
              '';
            });
          };
        };
      })
    ]
  );
}