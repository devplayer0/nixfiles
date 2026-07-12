{ lib, pkgs, ... }:
let
  # TODO: Move into nixpkgs
  mstpd = pkgs.mstpd.overrideAttrs {
    patches = [ ./mstpd.patch ];
    # Delete postInstall since it nukes the bridge-stp script we need
    postInstall = "";
  };
in
{
  environment = {
    systemPackages = [
      # For kernel to call bridge-stp (see ./pkgs/os-specific/linux/kernel/bridge-stp-helper.patch)
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
          if [ "$IFACE" = "lan" ]; then
            ${mstpd}/sbin/mstpctl setforcevers "$IFACE" rstp
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
          ExecStart = "${mstpd}/bin/bridge-stp restart";
          ExecReload = "${mstpd}/bin/bridge-stp restart_config";
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
