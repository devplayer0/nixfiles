{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf;
  inherit (lib.my) mkOpt';

  cfg = config.my.nvme;
  nvme-cli = pkgs.nvme-cli.override {
    libnvme = pkgs.libnvme.overrideAttrs (o: {
      patches = (if (o ? patches) then o.patches else [ ]) ++ [ ./libnvme-hostconf.patch ];
    });
  };

  hostNQN = "nqn.2014-08.org.nvmexpress:uuid:${cfg.uuid}";
  etc = prefix: {
    "${prefix}nvme/hostnqn".text = hostNQN;
    "${prefix}nvme/hostid".text = cfg.uuid;
  };
in
{
  options.my.nvme = with lib.types; {
    uuid = mkOpt' (nullOr str) null "NVMe host ID";
    boot = {
      nqn = mkOpt' (nullOr str) null "NQN to connect to on boot";
      address = mkOpt' str null "Address of NVMe-oF target.";
    };
  };

  config = mkIf (cfg.uuid != null) {
    environment = {
      systemPackages = [
        nvme-cli
      ];
      etc = etc "";
    };

    boot.initrd.systemd = mkIf (cfg.boot.nqn != null) {
      contents = etc "/etc/";
      extraBin.nvme = "${nvme-cli}/bin/nvme";

      services.connect-nvme = {
        description = "Connect NVMe-oF";
        before = [ "initrd-root-device.target" ];
        after = [ "systemd-networkd-wait-online.service" ];
        requires = [ "systemd-networkd-wait-online.service" ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${nvme-cli}/bin/nvme connect -t rdma -a ${cfg.boot.address} -n ${cfg.boot.nqn}";
          Restart = "on-failure";
          RestartSec = 10;
        };

        wantedBy = [ "initrd-root-device.target" ];
      };
    };
  };
}

