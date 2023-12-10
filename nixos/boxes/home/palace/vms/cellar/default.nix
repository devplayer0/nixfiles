{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.home) domain prefixes vips;
in
{
  nixos.systems.cellar = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      hi = {
        inherit domain;
        ipv4 = {
          address = net.cidr.host 80 prefixes.hi.v4;
          mask = 22;
          gateway = vips.hi.v4;
        };
      };
    };

    configuration = { lib, pkgs, modulesPath, config, assignments, allAssignments, ... }:
      let
        inherit (lib) mkMerge;
        inherit (lib.my) networkdAssignment;

        spdk = pkgs.spdk.overrideAttrs (o: {
          configureFlags = o.configureFlags ++ [ "--with-rdma" ];
        });
      in
      {
        imports = [
          "${modulesPath}/profiles/qemu-guest.nix"
        ];

        config = mkMerge [
          {
            boot = {
              kernelParams = [ "console=ttyS0,115200n8" ];
              blacklistedKernelModules = [ "nvme" ];
            };

            fileSystems = {
              "/boot" = {
                device = "/dev/disk/by-partuuid/f7562ee6-34c1-4e94-8ae7-c6e71794d563";
                fsType = "vfat";
              };
              "/nix" = {
                device = "/dev/disk/by-uuid/f31f6abd-0832-4014-a761-f3c3126d5739";
                fsType = "ext4";
              };
              "/persist" = {
                device = "/dev/disk/by-uuid/620364e3-3a30-4704-be80-8593516e7482";
                fsType = "ext4";
                neededForBoot = true;
              };
            };

            environment.systemPackages = with pkgs; [
              pciutils
              spdk
              (pkgs.writeShellScriptBin "spdk-rpc" ''
                exec ${pkgs.python3}/bin/python3 ${spdk.src}/scripts/rpc.py "$@"
              '')
            ];

            services = {
              netdata.enable = true;
            };

            systemd.services = {
              spdk-nvmf = {
                description = "SPDK NVMe-oF target";
                path = with pkgs; [
                  bash
                  python3
                  kmod
                  gawk
                  util-linux
                ];
                after = [ "systemd-networkd-wait-online@lan-hi.service" ];
                preStart = ''
                  ${spdk.src}/scripts/setup.sh
                '';
                serviceConfig.ExecStart = "${spdk}/bin/spdk_tgt -c ${./spdk_nvmf.json}";
                wantedBy = [ "multi-user.target" ];
              };
            };

            systemd.network = {
              links = {
                "10-lan-hi" = {
                  matchConfig.PermanentMACAddress = "52:54:00:cc:3e:70";
                  linkConfig = {
                    Name = "lan-hi";
                    MTUBytes = "9000";
                  };
                };
              };

              networks = {
                "80-vms" = mkMerge [
                  (networkdAssignment "lan-hi" assignments.hi)
                  {
                    networkConfig.DNS = [
                      (allAssignments.stream.hi.ipv4.address)
                      # (allAssignments.river.hi.ipv4.address)
                    ];
                  }
                ];
              };
            };

            my = {
              secrets.key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDcklmJp8xVRddNDU1DruKV+Ipim3Jtl6nE1oCWmpmZH";
              server.enable = true;
              deploy.node.hostname = "192.168.68.80";

              firewall = {
                tcp.allowed = [ 19999 ];
              };
            };
          }
        ];
      };
  };
}
