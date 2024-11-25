{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf;
  inherit (lib.my) mkOpt';

  cfg = config.my.nvme;
  nvme-cli = pkgs.nvme-cli.override {
    libnvme = pkgs.libnvme.overrideAttrs (o: rec {
      # TODO: Remove when 1.11.1 releases (see https://github.com/linux-nvme/libnvme/pull/914)
      version = "1.11.1";
      src = pkgs.fetchFromGitHub {
        owner = "linux-nvme";
        repo = "libnvme";
        rev = "v${version}";
        hash = "sha256-CEGr7PDOVRi210XvICH8iLYDKn8S9bGruBO4tycvsT8=";
      };
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
          extraConfig = ''
            DefaultTimeoutStartSec=20
            DefaultDeviceTimeoutSec=20
          '';

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
              ExecStart = "${nvme-cli}/bin/nvme connect -t rdma -a ${cfg.boot.address} -n ${cfg.boot.nqn}";
              Restart = "on-failure";
              RestartSec = 10;
            };

            wantedBy = [ "initrd-root-device.target" ];
          };
        };
      };
    };
  };
}

