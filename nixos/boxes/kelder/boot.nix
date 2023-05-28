{ lib, pkgs, ... }:
let
  plymouth-kelder = pkgs.runCommand "plymouth-kelder" {} ''
    target="$out"/share/plymouth/themes/kelder
    mkdir -p "$target"

    substituteAll ${./plymouth/kelder.plymouth} "$target"/kelder.plymouth
    cp ${./plymouth/kelder.script} "$target"/kelder.script
    cp ${./plymouth/kelder.png} "$target"/kelder.png
    cp ${./plymouth/bridge.png} "$target"/bridge.png
  '';
in
{
  boot.plymouth = {
    enable = true;
    themePackages = [ plymouth-kelder ];
    theme = "kelder";
  };

  systemd.services = {
    amogus-beep = {
      enable = true;
      description = "amogus sus";
      before = [ "plymouth-quit.service" ];

      path = with pkgs; [ beep ];
      serviceConfig = {
        RemainAfterExit = true;
        ExecStart = "${pkgs.python3}/bin/python ${./amogus_beep.py}";
        Type = "oneshot";
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
