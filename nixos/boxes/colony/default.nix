{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.colony) domain prefixes custRouting firewallForwards;
in
{
  imports = [ ./vms ];

  nixos.systems.colony = {
    system = "x86_64-linux";
    nixpkgs = "mine-stable";
    home-manager = "mine-stable";

    assignments = {
      routing = {
        name = "colony-routing";
        inherit domain;
        ipv4.address = net.cidr.host 2 prefixes.base.v4;
      };
      internal = {
        altNames = [ "vm" ];
        inherit domain;
        ipv4 = {
          address = net.cidr.host 0 prefixes.vip1;
          mask = 32;
          gateway = null;
          genPTR = false;
        };
        ipv6 = {
          iid = "::2";
          address = net.cidr.host 2 prefixes.base.v6;
        };
      };
      vms = {
        name = "colony-vms";
        inherit domain;
        ipv4 = {
          address = net.cidr.host 1 prefixes.vms.v4;
          gateway = null;
        };
        ipv6.address = net.cidr.host 1 prefixes.vms.v6;
      };
    };

    configuration = { lib, pkgs, modulesPath, config, systems, assignments, allAssignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        hardware = {
          enableRedistributableFirmware = true;
          cpu = {
            amd.updateMicrocode = true;
          };
          rasdaemon.enable = true;
        };

        boot = {
          kernelPackages = (lib.my.c.kernel.lts pkgs).extend (self: super: {
            kernel = super.kernel.override {
              structuredExtraConfig = with lib.kernel; {
                ACPI_APEI_PCIEAER = yes;
                PCIEAER = yes;
              };
            };
          });
          kernelModules = [ "kvm-amd" ];
          kernelParams = [
            "amd_iommu=on"
            "console=ttyS0,115200n8" "console=ttyS1,115200n8" "console=tty0"
            "systemd.setenv=SYSTEMD_SULOGIN_FORCE=1"
          ];
          initrd = {
            kernelModules = [ "dm-raid" ];
            availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" "sr_mod" ];
            systemd = {
              enable = true;
              # Onlu activate volumes needed for boot to prevent thin check from getting killed while switching root
              contents."/etc/lvm/lvm.conf".text = ''
                activation/auto_activation_volume_list = [ "main/colony-nix" "main/colony-persist" ]
              '';
            };
          };
        };

        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-uuid/C1C9-9CBC";
            fsType = "vfat";
          };
          "/nix" = {
            device = "/dev/main/colony-nix";
            fsType = "ext4";
          };
          "/persist" = {
            device = "/dev/main/colony-persist";
            fsType = "ext4";
            neededForBoot = true;
          };
          "/mnt/backup" = {
            device = "/dev/main/backup";
            fsType = "ext4";
          };
        };

        programs.ssh.knownHostsFiles = [
          lib.my.c.sshKeyFiles.rsyncNet
        ];

        services = {
          fstrim = lib.my.c.colony.fstrimConfig;
          lvm = {
            boot.thin.enable = true;
            dmeventd.enable = true;
          };

          netdata = {
            enable = true;
            config = {
              # Ignore the VCCM sensor (RAM voltage is 1.35V with XMP enabled)
              "plugin:freeipmi"."command options" = "ignore 5";
            };
          };

          smartd = {
            enable = true;
            autodetect = true;
            extraOptions = [ "-A /var/log/smartd/" "--interval=600" ];
          };
        };

        environment.systemPackages = with pkgs; [
          pciutils
          usbutils
          partclone
          lm_sensors
          linuxPackages.cpupower
          smartmontools
          xfsprogs
        ];

        systemd = {
          tmpfiles.rules = [
            "d /var/log/smartd 0755 root root"
          ];

          services = {
            "serial-getty@ttyS0".enable = true;
            "serial-getty@ttyS1".enable = true;
            lvm-activate-main = {
              description = "Activate remaining LVs";
              unitConfig.DefaultDependencies = false;
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${pkgs.lvm2.bin}/bin/vgchange -aay main";
              };
              wantedBy = [ "local-fs-pre.target" ];
            };

            rsync-lvm-meta = {
              description = "rsync lvm metadata backups / archives to rsync.net";
              serviceConfig = {
                Type = "oneshot";

                # Only run when no other process is using CPU or disk
                CPUSchedulingPolicy = "idle";
                IOSchedulingClass = "idle";
              };
              script = ''
                ${pkgs.rsync}/bin/rsync -av --delete --delete-after \
                  -e "${pkgs.openssh}/bin/ssh -i ${config.age.secrets."colony/rsync.key".path}" \
                  /etc/lvm/{archive,backup} zh2855@zh2855.rsync.net:colony/lvm/
              '';
              wantedBy = [ "borgthin-job-main.service" ];
              after = [ "borgthin-job-main.service" ];
            };
            borgthin-rsync = {
              description = "rsync borgthin backups to rsync.net";
              serviceConfig = {
                Type = "oneshot";

                # Only run when no other process is using CPU or disk
                CPUSchedulingPolicy = "idle";
                IOSchedulingClass = "idle";
              };
              script = ''
                ${pkgs.rsync}/bin/rsync -av --delete --delete-after \
                  -e "${pkgs.openssh}/bin/ssh -i ${config.age.secrets."colony/rsync.key".path}" \
                  /mnt/backup/main/ zh2855@zh2855.rsync.net:borg/colony/
              '';
              wantedBy = [ "borgthin-job-main.service" ];
              after = [ "borgthin-job-main.service" ];
            };
          };

          network = {
            links = {
              "10-wan0" = {
                matchConfig.MACAddress = "d0:50:99:fa:a7:99";
                linkConfig.Name = "wan0";
              };
              "10-wan1" = {
                matchConfig.MACAddress = "d0:50:99:fa:a7:9a";
                linkConfig.Name = "wan1";
              };
            };
            netdevs = {
              "25-base".netdevConfig = {
                Name = "base";
                Kind = "bridge";
              };
              "30-base-dummy".netdevConfig = {
                Name = "base0";
                Kind = "dummy";
              };

              "25-vms".netdevConfig = {
                Name = "vms";
                Kind = "bridge";
              };
              "30-vms-dummy".netdevConfig = {
                Name = "vms0";
                Kind = "dummy";
              };
            };

            networks = {
              "80-base" = mkMerge [
                (networkdAssignment "base" assignments.routing)
                (networkdAssignment "base" assignments.internal)
              ];
              "80-base-dummy" = {
                matchConfig.Name = "base0";
                networkConfig.Bridge = "base";
              };
              "80-base-ext" = {
                matchConfig.Name = "base-ext";
                networkConfig.Bridge = "base";
              };

              "80-vms" = mkMerge [
                (networkdAssignment "vms" assignments.vms)
                {
                  networkConfig = {
                    IPv6AcceptRA = mkForce false;
                    IPv6SendRA = true;
                  };
                  ipv6SendRAConfig = {
                    DNS = [ allAssignments.estuary.base.ipv6.address ];
                    Domains = [ config.networking.domain ];
                  };
                  ipv6Prefixes = [
                    {
                      ipv6PrefixConfig.Prefix = prefixes.vms.v6;
                    }
                  ];
                  routes = map (r: { routeConfig = r; }) [
                    {
                      Destination = prefixes.ctrs.v4;
                      Gateway = allAssignments.shill.routing.ipv4.address;
                    }
                    {
                      Destination = prefixes.ctrs.v6;
                      Gateway = allAssignments.shill.internal.ipv6.address;
                    }

                    {
                      Destination = allAssignments.shill.internal.ipv4.address;
                      Gateway = allAssignments.shill.routing.ipv4.address;
                    }

                    {
                      Destination = lib.my.c.tailscale.prefix.v4;
                      Gateway = allAssignments.shill.routing.ipv4.address;
                    }
                    {
                      Destination = lib.my.c.tailscale.prefix.v6;
                      Gateway = allAssignments.shill.internal.ipv6.address;
                    }
                    {
                      Destination = prefixes.qclk.v4;
                      Gateway = allAssignments.shill.routing.ipv4.address;
                    }

                    {
                      Destination = prefixes.jam.v6;
                      Gateway = allAssignments.shill.internal.ipv6.address;
                    }

                    {
                      Destination = prefixes.oci.v4;
                      Gateway = allAssignments.whale2.routing.ipv4.address;
                    }
                    {
                      Destination = prefixes.oci.v6;
                      Gateway = allAssignments.whale2.internal.ipv6.address;
                    }
                    {
                      Destination = allAssignments.whale2.internal.ipv4.address;
                      Gateway = allAssignments.whale2.routing.ipv4.address;
                    }

                    {
                      Destination = allAssignments.git.internal.ipv4.address;
                      Gateway = allAssignments.git.routing.ipv4.address;
                    }
                  ];
                }
              ];
              # Just so the vms interface will come up (in networkd's eyes), allowing dependant VMs to start.
              # Could tweak the `waitOnline` for a single VM, but this seems better overall?
              "80-vms-dummy" = {
                matchConfig.Name = "vms0";
                networkConfig.Bridge = "vms";
              };

              "90-vm-mail" = {
                matchConfig.Name = "vm-mail";
                address = [
                  "${custRouting.mail-vm}/32"
                  prefixes.mail.v6
                ];
                networkConfig = {
                  IPv6AcceptRA = false;
                  IPv6SendRA = true;
                };
                ipv6Prefixes = [
                  {
                    ipv6PrefixConfig.Prefix = prefixes.mail.v6;
                  }
                ];
                routes = map (r: { routeConfig = r; }) [
                  {
                    Destination = prefixes.mail.v4;
                    Scope = "link";
                  }
                ];
              };

              "90-vm-darts" = {
                matchConfig.Name = "vm-darts";
                address = [
                  "${custRouting.darts-vm}/32"
                  prefixes.darts.v6
                ];
                networkConfig = {
                  IPv6AcceptRA = false;
                  IPv6SendRA = true;
                };
                ipv6Prefixes = [
                  {
                    ipv6PrefixConfig.Prefix = prefixes.darts.v6;
                  }
                ];
                routes = map (r: { routeConfig = r; }) [
                  {
                    Destination = prefixes.darts.v4;
                    Scope = "link";
                  }
                ];
              };
            };
          };
        };

        #environment.etc."udev/udev.conf".text = "udev_log=debug";
        #systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
        virtualisation = {
          cores = 8;
          memorySize = 8192;
          qemu.options = [
            "-machine q35"
            "-accel kvm,kernel-irqchip=split"
            "-device intel-iommu,intremap=on,caching-mode=on"
          ];
        };

        my = {
          #deploy.generate.system.mode = "boot";
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIijqzAWF6OxKr4aeCa1TAc5xGn4rdIjVTt0wAPU6uY";
            files = {
              "colony/borg-pass.txt" = {};
              "colony/rsync.key" = {};
            };
          };

          server.enable = true;

          firewall = {
            trustedInterfaces = [ "vms" ];
            nat.forwardPorts."${allAssignments.estuary.internal.ipv4.address}" = firewallForwards allAssignments;
            extraRules = ''
              define cust = { vm-mail, vm-darts }
              table inet filter {
                chain forward {
                  # Trust that the outer firewall has done the filtering!
                  iifname base oifname { vms, $cust } accept
                  iifname $cust accept # trust for now...
                }
              }
            '';
          };

          borgthin = {
            enable = true;
            jobs = {
              main = {
                repo = "/mnt/backup/main";
                passFile = config.age.secrets."colony/borg-pass.txt".path;
                lvs = map (lv: "main/${lv}") [
                  "colony-persist"
                  "vm-shill-persist"
                  "minio"
                  "oci"
                  "vm-estuary-persist"
                  "vm-whale2-persist"
                  "vm-mail-data"
                  "vm-git-persist"
                  "git"
                ];
                compression = "zstd,5";
                extraCreateArgs = [ "--stats" ];
                prune.keep = {
                  last = 1;
                  within = "1d";
                  daily = 7;
                  weekly = 4;
                  monthly = 12;
                  yearly = -1;
                };
              };
            };
          };
        };
      };
  };
}
