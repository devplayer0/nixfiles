{ lib, pkgs, ... }:
let
  # TODO: Move into nixpkgs
  mstpd = pkgs.mstpd.overrideAttrs {
    patches = [ ./mstpd.patch ];
    # Delete postInstall since it nukes the bridge-stp script we need
    postInstall = "";
  };
  configureRSTP = pkgs.writeShellScript "configure-router-rstp" ''
    set -eu
    [ "$1" = lan ] || exit 0
    event_port="''${2:-}"
    ${mstpd}/bin/mstpctl addbridge lan
    ${mstpd}/bin/mstpctl setforcevers lan rstp
    for port in lan-dave lan-jim; do
      if [ "$event_port" = "$port" ] || [ -e "/sys/class/net/lan/brif/$port" ]; then
        case "$port" in
          lan-dave) cost=10 ;;
          lan-jim) cost=100 ;;
        esac
        # networkd can report configuration before mstpd has registered the port.
        configured=false
        for attempt in {1..50}; do
          if ${mstpd}/bin/mstpctl setportpathcost lan "$port" "$cost"; then
            configured=true
            break
          fi
          ${pkgs.coreutils}/bin/sleep 0.2
        done
        if [ "$configured" = false ]; then
          echo "Failed to configure RSTP cost for $port" >&2
          exit 1
        fi
      fi
    done
  '';
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
        config_cmd=${configureRSTP}
      '';
    };
  };

  services = {
    networkd-dispatcher.rules = {
      configure-mstpd = {
        onState = [ "configured" ];
        script = ''
          #!${pkgs.runtimeShell}
          # A queued event can retain the interface's name from before a rename.
          if [ -d /sys/class/net/lan/bridge ]; then
            ${configureRSTP} lan "$IFACE"
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
