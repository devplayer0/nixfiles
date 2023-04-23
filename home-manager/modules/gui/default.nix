{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf mkMerge mkForce;
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
            noto-fonts-emoji

            python310Packages.python-lsp-server
            nil # nix language server
            zls # zig language server
          ];
        };

        programs = {
          gh = {
            enable = true;
            settings = {
              git_protocol = "ssh";
            };
          };

          alacritty = {
            enable = true;
            settings = {
              font.normal.family = "SauceCodePro Nerd Font Mono";
            };
          };

          kitty = {
            enable = true;
            font.name = "SauceCodePro Nerd Font Mono";
            settings = {
              background_opacity = "0.8";
              tab_bar_edge = "top";
            };
          };

          helix = {
            enable = true;
            settings = {
              keys = {
                normal = {
                  "^" = "goto_first_nonwhitespace";
                  "$" = "goto_line_end";
                };
              };
              editor = {
                whitespace = {
                  render.newline = "all";
                };
                indent-guides = {
                  render = true;
                  character = "┊";
                };
              };
            };
          };
        };
      }
      (mkIf (cfg.standalone && !pkgs.stdenv.isDarwin) {
        systemd.user = {
          services = {
            wait-for-sway = {
              Unit = {
                Description = "Wait for sway to be ready";
                Before = "graphical-session.target";
              };
              Service = {
                Type = "oneshot";
                ExecStart = toString (pkgs.writeShellScript "wait-for-sway.sh" ''
                  until ${pkgs.sway}/bin/swaymsg -t get_version -q; do
                    ${pkgs.coreutils}/bin/sleep 0.1
                  done
                  ${pkgs.coreutils}/bin/sleep 0.5
                '');
                RemainAfterExit = true;
              };
              Install.RequiredBy = [ "sway-session.target" ];
            };
          };
        };

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
          packages = with pkgs; [
            wtype
            wl-clipboard
            wev
            wdisplays

            pavucontrol
            libsecret

            playerctl
            spotify
          ];

          pointerCursor = {
            package = pkgs.vanilla-dmz;
            name = "Vanilla-DMZ";
            size = 16;
            gtk.enable = true;
          };
        };

        fonts.fontconfig.enable = true;

        xsession.preferStatusNotifierItems = true;
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
                window.titlebar = false;

                modifier = "Mod4";
                terminal = "kitty";
                keybindings =
                  let
                    cfg = config.wayland.windowManager.sway.config;
                    mod = cfg.modifier;
                  in
                  lib.mkOptionDefault {
                    "${mod}+d" = null;
                    "${mod}+x" = "exec ${cfg.menu}";
                    "${mod}+q" = "kill";
                    "${mod}+Shift+q" = "exec swaynag -t warning -m 'bruh you really wanna kill sway?' -b 'ye' 'systemctl --user stop graphical-session.target && swaymsg exit'";
                    "${mod}+Shift+s" = "exec flameshot gui";
                    "${mod}+Shift+e" = "exec rofi -show emoji";
                    # Config for this doesn't seem to work :/
                    "${mod}+c" = ''exec rofi -show calc -calc-command "echo -n '{result}' | ${pkgs.wl-clipboard}/bin/wl-copy"'';

                    "XF86AudioRaiseVolume" = "exec ${pkgs.pamixer}/bin/pamixer -i 5";
                    "XF86AudioLowerVolume" = "exec ${pkgs.pamixer}/bin/pamixer -d 5";
                    "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
                    "XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
                    "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
                    "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
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

        gtk = {
          enable = true;
          theme = {
            name = "Numix";
            package = pkgs.numix-gtk-theme;
          };
          iconTheme = {
            name = "Numix";
            package = pkgs.numix-icon-theme;
          };
        };
        qt = {
          enable = true;
          platformTheme = "gtk";
        };

        services = {
          swaync = {
            enable = true;
            settings = {
              widgets = [ "title" "dnd" "mpris" "notifications" ];
            };
          };

          flameshot = {
            enable = true;
            settings = {
              General = {
                disabledTrayIcon = true;
                savePath = "/tmp/screenshots";
                savePathFixed = false;
              };
            };
          };

          playerctld.enable = true;
          spotifyd = {
            enable = false;
            package = pkgs.spotifyd.override {
              withMpris = true;
              withKeyring = true;
            };
            settings.global = {
              username = "devplayer0";
              use_keyring = true;
              use_mpris = true;
              backend = "pulseaudio";
              bitrate = 320;
              device_type = "computer";
            };
          };
        };

        programs = {
          git = {
            enable = true;
            diff-so-fancy.enable = true;
            userEmail = "jackos1998@gmail.com";
            userName = "Jack O'Sullivan";
            extraConfig = {
              pull.rebase = true;
            };
          };

          waybar = import ./waybar.nix { inherit lib pkgs config; };
          rofi = {
            enable = true;
            font = "SauceCodePro Nerd Font Mono 14";
            plugins = with pkgs; [
              rofi-calc
              rofi-emoji
            ];
            extraConfig = {
              modes = "window,run,ssh,filebrowser,calc,emoji";
              emoji-mode = "copy";
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
