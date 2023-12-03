{ lib, pkgs, ... }:
let
  # TODO: Move into nixpkgs
  mstpd = pkgs.mstpd.overrideAttrs {
    patches = [ ./mstpd.patch ];
  };
in
{
  environment = {
    systemPackages = [
      mstpd
    ];
    etc = {
      "bridge-stp.conf".text = ''
        MANAGE_MSTPD=n
        MSTP_BRIDGES=lan
      '';
    };
  };

  services = {
    networkd-dispatcher.rules = {
      configure-mstpd = {
        onState = [ "routable" ];
        script = ''
          #!${pkgs.runtimeShell}
          if [ $IFACE = "lan" ]; then
            ${mstpd}/sbin/mstpctl setforcevers $IFACE rstp
          fi
        '';
      };
    };
  };

  systemd = {
    services = {
      mstpd = {
        description = "MSTP daemon";
        before = [ "network-pre.target" ];
        serviceConfig = {
          Type = "forking";
          ExecStart = "${mstpd}/sbin/bridge-stp restart";
          ExecReload = "${mstpd}/sbin/bridge-stp restart_config";
          PIDFile = "/run/mstpd.pid";
          Restart = "always";
          PrivateTmp = true;
          ProtectHome = true;
        };
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
