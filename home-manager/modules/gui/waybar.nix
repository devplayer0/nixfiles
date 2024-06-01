{ lib, pkgs, config, font, ... }:
let
  inherit (lib) mkIf mkDefault mkMerge mkForce;

  cfg = config.my.gui;
  pkg = pkgs.waybar.override { withMediaPlayer = true; };
in
{
  enable = true;
  package = pkg;
  systemd.enable = true;
  settings = {
    mainBar = {
      height = 30;
      spacing = 4;
      modules-left = [ "sway/workspaces" "sway/mode" "custom/media" ];
      modules-center = [ "sway/window" ];
      modules-right = [
        "idle_inhibitor" "cpu" "memory" "temperature" "backlight"
        "battery" "pulseaudio" "clock" "network" "tray" "custom/notification"
      ];
      # Modules configuration
      # "sway/workspaces": {
      #     "disable-scroll": true,
      #     "all-outputs": true,
      #     "format": "{name}: {icon}",
      #     "format-icons": {
      #         "1": "",
      #         "2": "",
      #         "3": "",
      #         "4": "",
      #         "5": "",
      #         "urgent": "",
      #         "focused": "",
      #         "default": ""
      #     }
      # },
      keyboard-state = {
        numlock = true;
        capslock = true;
        format = "{name} {icon}";
        format-icons = {
          locked = "";
          unlocked = "";
        };
      };
      "sway/mode".format = "<span style=\"italic\">{}</span>";
      idle_inhibitor = {
        format = "{icon}";
        format-icons = {
          activated = "";
          deactivated = "";
        };
      };
      tray = {
        # "icon-size": 21,
        spacing = 10;
      };
      clock = {
        # "timezone": "America/New_York",
        # format-alt = "{:%Y-%m-%d}";
        interval = 1;
        format = "{:%F %T}";
        tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      };
      cpu = {
        format = "{usage}% ";
        tooltip = false;
      };
      memory.format = "{}% ";
      temperature = {
        # "thermal-zone": 2,
        # "hwmon-path": "/sys/class/hwmon/hwmon2/temp1_input",
        critical-threshold = 80;
        # "format-critical": "{temperatureC}°C {icon}",
        format = "{temperatureC}°C {icon}";
        format-icons = [ "" "" "" ];
      };
      backlight = {
          # "device": "acpi_video1",
          format = "{percent}% {icon}";
          format-icons = [ "" "" "" "" "" "" "" "" "" ];
      };
      battery = {
        states = {
          # "good": 95,
          warning = 30;
          critical = 15;
        };
        format = "{capacity}% {icon}";
        format-charging = "{capacity}% ";
        format-plugged = "{capacity}% ";
        format-alt = "{time} {icon}";
        # "format-good": "", // An empty format will hide the module
        # "format-full": "",
        format-icons = [ "" "" "" "" "" ];
      };
      network = {
        # "interface": "wlp2*", // (Optional) To force the use of this interface
        format-wifi = "{essid} ({signalStrength}%) ";
        format-ethernet = "{ipaddr}/{cidr} ";
        tooltip-format = "{ifname} via {gwaddr} ";
        format-linked = "{ifname} (No IP) ";
        format-disconnected = "Disconnected ⚠";
        format-alt = "{ifname}: {ipaddr}/{cidr}";
      };
      pulseaudio = {
        # "scroll-step": 1, // %, can be a float
        format = "{volume}% {icon} {format_source}";
        format-bluetooth = "{volume}% {icon} {format_source}";
        format-bluetooth-muted = " {icon} {format_source}";
        format-muted = " {format_source}";
        format-source = "{volume}% ";
        format-source-muted = "";
        format-icons = {
          headphone = "";
          hands-free = "";
          headset = "";
          phone = "";
          portable = "";
          car = "";
          default = [ "" "" "" ];
        };
        on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
      };
      "custom/media" = {
        # TODO: waybar has a built-in MPRIS module now
        format = "{icon} {}";
        return-type = "json";
        max-length = 40;
        format-icons = {
          spotify = "";
          default = "";
        };
        escape = true;
        exec = ''${pkg}/bin/waybar-mediaplayer.py 2> /dev/null'';
        # "exec": "$HOME/.config/waybar/mediaplayer.py --player spotify 2> /dev/null" // Filter player based on name
      };
      "custom/notification" = {
        tooltip = false;
        format = "{icon}";
        format-icons = {
          notification = "<span foreground='red'><sup></sup></span>";
          none = "";
          dnd-notification = "<span foreground='red'><sup></sup></span>";
          dnd-none = "";
        };
        return-type = "json";
        exec = "${config.my.swaync.package}/bin/swaync-client -swb";
        on-click = "${config.my.swaync.package}/bin/swaync-client -t -sw";
        on-click-right = "${config.my.swaync.package}/bin/swaync-client -d -sw";
        escape = true;
      };
    };
  };
  style = ''
    * {
      font-size: 12px;
      font-family: ${font.name};
      /*font-family: monospace;*/
    }

    window#waybar {
      background: #292b2e;
      color: #fdf6e3;
    }

    #custom-right-arrow-dark,
    #custom-left-arrow-dark {
      color: #1a1a1a;
    }
    #custom-right-arrow-light,
    #custom-left-arrow-light {
      color: #292b2e;
      background: #1a1a1a;
    }

    #workspaces,
    #clock.1,
    #clock.2,
    #clock.3,
    #pulseaudio,
    #memory,
    #cpu,
    #battery,
    #disk,
    #tray {
      background: #1a1a1a;
    }

    #workspaces button {
      padding: 0 2px;
      color: #fdf6e3;
    }
    #workspaces button.focused {
      color: #268bd2;
    }
    #workspaces button:hover {
      box-shadow: inherit;
      text-shadow: inherit;
    }
    #workspaces button:hover {
      background: #1a1a1a;
      border: #1a1a1a;
      padding: 0 3px;
    }

    #pulseaudio {
      color: #268bd2;
    }
    #memory {
      color: #2aa198;
    }
    #cpu {
      color: #6c71c4;
    }
    #battery {
      color: #859900;
    }
    #disk {
      color: #b58900;
    }

    #clock,
    #pulseaudio,
    #memory,
    #cpu,
    #battery,
    #disk {
      padding: 0 10px;
    }
  '';
}
