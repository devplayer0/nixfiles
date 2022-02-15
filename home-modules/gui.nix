{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf mkDefault;
  inherit (lib.my) mkBoolOpt';

  cfg = config.my.gui;
in
{
  options.my.gui = {
    enable = mkBoolOpt' true "Enable settings and packages meant for graphical systems";
  };

  config = mkIf cfg.enable {
    programs = {
      lsd = {
        enable = mkDefault true;
        enableAliases = mkDefault true;
      };

      starship = {
        enable = mkDefault true;
        settings = {
          aws.disabled = true;
        };
      };
    };

    home = {
      packages = with pkgs; [
        (pkgs.nerdfonts.override {
          fonts = [ "DroidSansMono" "SourceCodePro" ];
        })
      ];
    };
  };
}
