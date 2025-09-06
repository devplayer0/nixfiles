{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf;
  inherit (lib.my) mkOpt';

  cfg = config.my.nvme;

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
        pkgs.nvme-cli
      ];
      etc = etc "";
    };

    boot = mkIf (cfg.boot.nqn != null) {
      initrd = {
        availableKernelModules = [ "rdma_cm" "iw_cm" "ib_cm" "nvme_core" "nvme_rdma" ];
        kernelModules = [ "nvme-fabrics" ];
        systemd = {
          contents = etc "/etc/";
          extraBin = with pkgs; {
            dmesg = "${util-linux}/bin/dmesg";
            ip = "${iproute2}/bin/ip";
            nvme = "${nvme-cli}/bin/nvme";
          };

          network = {
            enable = true;
            wait-online.enable = true;
          };

          services.connect-nvme = {
            description = "Connect NVMe-oF";
            before = [ "initrd-root-device.target" ];
            after = [ "systemd-networkd-wait-online.service" ];
            requires = [ "systemd-networkd-wait-online.service" ];

            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.nvme-cli}/bin/nvme connect -t rdma -a ${cfg.boot.address} -n ${cfg.boot.nqn} -q ${hostNQN}";
              Restart = "on-failure";
              RestartSec = 10;
            };

            wantedBy = [ "initrd-root-device.target" ];
          };
        # TODO: Remove when 25.11 releases
        } // (if (lib.versionAtLeast lib.my.upstreamRelease "25.11") then {
          settings.Manager = {
            DefaultTimeoutStartSec = 20;
            DefaultDeviceTimeoutSec = 20;
          };
        } else {
          extraConfig = ''
            DefaultTimeoutStartSec=20
            DefaultDeviceTimeoutSec=20
          '';
        });
      };
    };
  };
}

