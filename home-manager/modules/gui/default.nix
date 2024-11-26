{ lib, pkgs', pkgs, config, ... }:
let
  inherit (lib) genAttrs mkIf mkMerge mkForce mapAttrs mkOptionDefault;
  inherit (lib.my) mkBoolOpt';

  cfg = config.my.gui;

  font = {
    package = pkgs.monocraft;
    name = "Monocraft";
    size = 10;
  };

  doomWad = pkgs.fetchurl {
    url = "https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad";
    hash = "sha256-HX1DvlAeZ9kn5BXguPPinDvzMHXoWXIYFvZSpSbKx3E=";
  };

  doomsaver = pkgs.runCommand "doomsaver" {
    inherit (pkgs) windowtolayer;
    chocoDoom = pkgs.chocolate-doom2xx;
    python = pkgs.python3.withPackages (ps: [ ps.filelock ]);
    inherit doomWad;
    enojy = ./enojy.jpg;
  } ''
    mkdir -p "$out"/bin
    substituteAll ${./screensaver.py} "$out"/bin/doomsaver
    chmod +x "$out"/bin/doomsaver
  '';
in
{
  options.my.gui = {
    enable = mkBoolOpt' true "Enable settings and packages meant for graphical systems";
    manageGraphical = mkBoolOpt' false "Configure the graphical session";
    standalone = mkBoolOpt' false "Enable settings for fully Nix managed systems";
  };

  config = mkIf cfg.enable (mkMerge [
      {
        home = {
          packages = with pkgs; [
            xdg-utils

            font.package
            (nerdfonts.override {
              fonts = [ "DroidSansMono" "SourceCodePro" ];
            })
            noto-fonts-emoji

            grim
            slurp
            swappy

            python3Packages.python-lsp-server
            nil # nix language server
            zls # zig language server
            rust-analyzer

            cowsay
            fortune
            jp2a
            terminaltexteffects
            screenfetch
            neofetch
            cmatrix
            doomsaver

            xournalpp
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
              general.import = [ ./alacritty-xterm.toml ];

              font = {
                size = font.size;
                normal = {
                  family = font.name;
                  style = "Regular";
                };
              };
            };
          };

          kitty = {
            enable = true;
            inherit font;
            settings = {
              background_opacity = "0.65";
              tab_bar_edge = "top";
              shell_integration = "no-sudo";
              font_features = "${font.name} -liga";
            };
          };

          termite = {
            enable = true;
            font = "${font.name} ${toString font.size}";
            backgroundColor = "rgba(0, 0, 0, 0.8)";
          };

          foot = {
            enable = true;
            settings = {
              main = {
                font = "${font.name}:size=${toString font.size}";
              };
              colors = {
                alpha = 0.8;
                background = "000000";
              };
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

      (mkIf (cfg.manageGraphical && !pkgs.stdenv.isDarwin) {
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

            activate-linux = {
              Unit = {
                Description = "Linux activation watermark";
                After = "graphical-session.target";
                PartOf = "graphical-session.target";
              };
              Service = {
                Type = "simple";
                ExecStart = "${pkgs.activate-linux}/bin/activate-linux";
              };
              Install.RequiredBy = [ "graphical-session.target" ];
            };
          };
        };

        home = {
          packages = with pkgs; [
            wtype
            wl-clipboard
            wev
            wdisplays
            swaysome

            pavucontrol
            libsecret

            playerctl
            spotify
          ];

          pointerCursor = {
            package = pkgs.posy-cursors;
            name = "Posy_Cursor";
            size = 32;
            gtk.enable = true;
            x11.enable = true;
          };
        };

        fonts.fontconfig.enable = true;

        xsession.preferStatusNotifierItems = true;
        wayland = {
          windowManager = {
            sway =
            let
              cfg = config.wayland.windowManager.sway.config;
              mod = cfg.modifier;

              renameWs = pkgs.writeShellScript "sway-rename-ws" ''
                focused_ws="$(swaymsg -t get_workspaces | jq ".[] | select(.focused)")"
                focused_num="$(jq -r ".num" <<< "$focused_ws")"
                focused_name="$(jq -r ".name" <<< "$focused_ws")"
                placeholder="$(sed -E 's/[0-9]+: //' <<< "$focused_name")"

                name="$(rofi -dmenu -p "rename ws $focused_num" -theme+entry+placeholder "\"$placeholder\"")"
                if [ -n "$name" ]; then
                  swaymsg rename workspace "$focused_name" to "$focused_num: $name"
                fi
              '';
              clearWsName = pkgs.writeShellScript "sway-clear-ws-name" ''
                focused_ws="$(swaymsg -t get_workspaces | jq ".[] | select(.focused)")"
                focused_num="$(jq -r ".num" <<< "$focused_ws")"
                focused_name="$(jq -r ".name" <<< "$focused_ws")"

                swaymsg rename workspace "$focused_name" to "$focused_num"
              '';
            in
            {
              enable = true;
              xwayland = true;
              extraConfigEarly = ''
                set $mod ${mod}
              '';
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
                keybindings = mapAttrs (k: mkOptionDefault) {
                  "${mod}+Left" = "focus left";
                  "${mod}+Down" = "focus down";
                  "${mod}+Up" = "focus up";
                  "${mod}+Right" = "focus right";

                  "${mod}+Shift+Left" = "move left";
                  "${mod}+Shift+Down" = "move down";
                  "${mod}+Shift+Up" = "move up";
                  "${mod}+Shift+Right" = "move right";

                  "${mod}+b" = "splith";
                  "${mod}+v" = "splitv";
                  "${mod}+f" = "fullscreen toggle";
                  "${mod}+a" = "focus parent";

                  "${mod}+s" = "layout stacking";
                  "${mod}+w" = "layout tabbed";
                  "${mod}+e" = "layout toggle split";

                  "${mod}+Shift+space" = "floating toggle";
                  "${mod}+space" = "focus mode_toggle";

                  "${mod}+1" = "workspace number 1";
                  "${mod}+2" = "workspace number 2";
                  "${mod}+3" = "workspace number 3";
                  "${mod}+4" = "workspace number 4";
                  "${mod}+5" = "workspace number 5";
                  "${mod}+6" = "workspace number 6";
                  "${mod}+7" = "workspace number 7";
                  "${mod}+8" = "workspace number 8";
                  "${mod}+9" = "workspace number 9";
                  "${mod}+0" = "workspace number 10";

                  "${mod}+Shift+1" =
                    "move container to workspace number 1";
                  "${mod}+Shift+2" =
                    "move container to workspace number 2";
                  "${mod}+Shift+3" =
                    "move container to workspace number 3";
                  "${mod}+Shift+4" =
                    "move container to workspace number 4";
                  "${mod}+Shift+5" =
                    "move container to workspace number 5";
                  "${mod}+Shift+6" =
                    "move container to workspace number 6";
                  "${mod}+Shift+7" =
                    "move container to workspace number 7";
                  "${mod}+Shift+8" =
                    "move container to workspace number 8";
                  "${mod}+Shift+9" =
                    "move container to workspace number 9";
                  "${mod}+Shift+0" =
                    "move container to workspace number 10";

                  "${mod}+Shift+minus" = "move scratchpad";
                  "${mod}+minus" = "scratchpad show";

                  "${mod}+Return" = "exec ${cfg.terminal}";
                  "${mod}+r" = "mode resize";
                  "${mod}+d" = null;
                  "${mod}+l" = "exec ${doomsaver}/bin/doomsaver";
                  "${mod}+q" = "kill";
                  "${mod}+Shift+c" = "reload";
                  "${mod}+Shift+q" = "exec swaynag -t warning -m 'bruh you really wanna kill sway?' -b 'ye' 'systemctl --user stop graphical-session.target && swaymsg exit'";

                  # rofi
                  "${mod}+x" = "exec ${cfg.menu}";
                  "${mod}+Shift+x" = "exec rofi -show drun";
                  "${mod}+Shift+e" = "exec rofi -show emoji";
                  # Config for this doesn't seem to work :/
                  "${mod}+c" = ''exec rofi -show calc -calc-command "echo -n '{result}' | ${pkgs.wl-clipboard}/bin/wl-copy"'';
                  "${mod}+Shift+r" = "exec ${renameWs}";
                  "${mod}+Shift+n" = "exec ${clearWsName}";

                  # Screenshots
                  "${mod}+Shift+d" = ''exec grim - | swappy -f -'';
                  "${mod}+Shift+s" = ''exec grim -g "$(slurp)" - | swappy -f -'';

                  "XF86MonBrightnessDown" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%-";
                  "XF86MonBrightnessUp" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set +5%";

                  "XF86AudioRaiseVolume" = "exec ${pkgs.pamixer}/bin/pamixer -i 5";
                  "XF86AudioLowerVolume" = "exec ${pkgs.pamixer}/bin/pamixer -d 5";
                  "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play";
                  "XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl pause";
                  "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
                  "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
                };
                keycodebindings = {
                  # keycode for XF86AudioPlayPause (no sym for some reason)
                  "172" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
                };

                menu = "rofi -show run";
                bars = mkForce [ ];
              };
              extraConfig = ''
                include ${./swaysome.conf}
              '';

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
          font.name = font.name;
        };
        qt = {
          enable = true;
          platformTheme.name = "gtk";
        };

        services = {
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
            lfs.enable = true;
            extraConfig = {
              pull.rebase = true;
            };
          };

          waybar = import ./waybar.nix { inherit lib pkgs config font; };
          rofi = {
            package = pkgs.rofi-wayland;
            enable = true;
            font = "${font.name} ${toString font.size}";
            plugins = with pkgs; (map (p: p.override { rofi-unwrapped = rofi-wayland-unwrapped; }) [
              rofi-calc
            ]) ++ [
              rofi-emoji-wayland
            ];
            extraConfig = {
              modes = "window,run,ssh,filebrowser,calc,emoji";
              emoji-mode = "copy";
            };
          };
          swaylock = {
            enable = true;
            # need to use system swaylock for PAM reasons
            package = pkgs.runCommandWith { name = "swaylock-dummy"; } ''mkdir $out'';
          };

          chromium = {
            enable = true;
            package = (pkgs'.unstable.chromium.override { enableWideVine = true; }).overrideAttrs (old: {
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

        xdg = {
          mimeApps = {
            enable = true;
            defaultApplications = genAttrs [
              "text/html"
              "x-scheme-handler/http"
              "x-scheme-handler/https"
              "x-scheme-handler/about"
              "x-scheme-handler/unknown"
            ] (_: "chromium-browser.desktop");
          };
        };

        my = {
          swaync = {
            enable = true;
            settings = {
              widgets = [ "title" "dnd" "mpris" "notifications" ];
            };
          };
        };
      })

      (mkIf (cfg.standalone && !pkgs.stdenv.isDarwin) {
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
      })
    ]
  );
}
