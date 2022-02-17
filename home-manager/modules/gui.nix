{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf mkDefault mkMerge;
  inherit (lib.my) mkBoolOpt';

  cfg = config.my.gui;
in
{
  options.my.gui = {
    enable = mkBoolOpt' true "Enable settings and packages meant for graphical systems";
  };

  config = mkMerge [
    (mkIf cfg.enable {
      home = {
        packages = with pkgs; [
          (nerdfonts.override {
            fonts = [ "DroidSansMono" "SourceCodePro" ];
          })
        ];
      };
    })
  ];
}
