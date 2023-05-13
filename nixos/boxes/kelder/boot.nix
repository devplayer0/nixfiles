{ pkgs, ... }: {
  boot.plymouth = {
    enable = true;
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
