{ lib, pkgs, extendModules, modulesPath, options, config, ... }:
let
  inherit (lib) recursiveUpdate mkOption mkDefault mkIf mkMerge mkForce flatten optional;
  inherit (lib.my) mkBoolOpt' dummyOption;

  cfg = config.my.build;

  allHardware = (optional config.my.build.allHardware { imports = [ "${modulesPath}/profiles/all-hardware.nix" ]; });

  asDevVM = extendModules {
    modules = [
      "${modulesPath}/virtualisation/qemu-vm.nix"
      { my.build.isDevVM = true; }
    ];
  };
  asISO = extendModules {
    modules = flatten [
      "${modulesPath}/installer/cd-dvd/iso-image.nix"
      allHardware
      {
        # Doesn't work right now... (missing /dev/root)
        boot.initrd.systemd.enable = false;

        isoImage = {
          makeEfiBootable = true;
          makeUsbBootable = true;
          # Not necessarily an installer
          appendToMenuLabel = mkDefault "";

          squashfsCompression = "zstd -Xcompression-level 8";
        };
      }
    ];
  };
  asContainer = extendModules {
    modules = [
      {
        boot.isContainer = true;
      }
    ];
  };
  asKexecTree = extendModules {
    modules = flatten [
      "${modulesPath}/installer/netboot/netboot.nix"
      allHardware
      (mkIf config.boot.initrd.systemd.enable {
        boot.initrd.systemd.services.setup-overlay-dirs = {
          description = "Create overlayfs dirs";
          after = [ "sysroot-nix-.rw\\x2dstore.mount" ];
          before = [ "sysroot-nix-store.mount" ];
          script = ''
            mkdir /sysroot/nix/.rw-store/{store,work}
          '';
          wantedBy = [ "initrd-fs.target" ];
        };

        fileSystems."/nix/store" = mkForce {
          fsType = "overlay";
          device = "overlay";
          options = [
            "lowerdir=/sysroot/nix/.ro-store"
            "upperdir=/sysroot/nix/.rw-store/store"
            "workdir=/sysroot/nix/.rw-store/work"
          ];
        };

        systemd.units."nix-store.mount".enable = false;
      })
    ];
  };

  asNetboot = extendModules {
    modules = flatten [
      allHardware
      ({ pkgs, config, ... }:
      let 
        initrdNbdWrapper = pkgs.writeCBin "nbd-wrapper" ''
          #include <stdio.h>
          #include <unistd.h>

          int main(int argc, char **argv) {
            if (argc < 3) {
              fprintf(stderr, "usage: %s <export> <server>\n", argv[0]);
              return -1;
            }

            argv[0][0] = '@';
            char* args[] = {
              "@", "-nofork", "-N", argv[1], argv[2], "/dev/nbd0", NULL
            };
            execv("${pkgs.nbd}/bin/nbd-client", args);
            return 0;
          };
        '';
        nbd = pkgs.nbd.overrideAttrs (o: {
          # TODO: Remove once this makes it to us
          # https://github.com/NixOS/nixpkgs/commit/52f1d9b03ae38126e7f648634fcad35897f464ed
          configureFlags = [ "--sysconfdir=/etc" ];
        });
      in
      {
        boot = {
          loader.grub.enable = false;
          kernelParams = [ "console=ttyS0,115200n8" ];
          initrd = {
            kernelModules = [ "nbd" ];
            
            systemd = {
              storePaths = with pkgs; [
                gnused
                nbd
                initrdNbdWrapper
                netcat
              ];
              extraBin = with pkgs; {
                dmesg = "${util-linux}/bin/dmesg";
                ip = "${iproute2}/bin/ip";
                nbd-client = "${nbd}/bin/nbd-client";
              };
              extraConfig = ''
                DefaultTimeoutStartSec=10
                DefaultDeviceTimeoutSec=10
              '';

              network = {
                enable = true;
                wait-online.enable = true;

                networks."10-nbd" = {
                  matchConfig.Name = "et-nbd";
                  DHCP = "yes";
                };
              };

              services = {
                # gennbdtab = {
                #   description = "Generate nbdtab";
                #   script = ''
                #     get_cmdline() {
                #       ${pkgs.gnused}/bin/sed -rn "s/^.*$1=(\\S+).*\$/\\1/p" < /proc/cmdline
                #     }

                #     e="$(get_cmdline nbd_export)"
                #     s="$(get_cmdline nbd_server)"
                #     echo "Setting nbdtab for $e @ $s"
                #     echo "nbd0 $s $e persist" > /etc/nbdtab
                #   '';
                #   serviceConfig.Type = "oneshot";
                #   # wantedBy = [ "initrd-root-device.target" ];
                # };
                nbd = {
                  description = "NBD Nix store";
                  # before = [ "initrd-root-device.target" ];
                  # after = [ "gennbdtab.service" "systemd-networkd-wait-online.service" ];
                  # wants = [ "gennbdtab.service" "systemd-networkd-wait-online.service" ];
                  # after = [ "systemd-networkd-wait-online.service" ];
                  # wants = [ "systemd-networkd-wait-online.service" ];

                  script = ''
                    get_cmdline() {
                      ${pkgs.gnused}/bin/sed -rn "s/^.*$1=(\\S+).*\$/\\1/p" < /proc/cmdline
                    }
                    s="$(get_cmdline nbd_server)"
                    until ${pkgs.netcat}/bin/nc -zv "$s" 22; do
                      sleep 0.1
                    done
                    exec ${nbd}/bin/nbd-client -systemd-mark -N "$(get_cmdline nbd_export)" "$s" /dev/nbd0
                    # exec ${initrdNbdWrapper}/bin/nbd-wrapper "$(get_cmdline nbd_export)" "$(get_cmdline nbd_server)"
                  '';
                  unitConfig = {
                    IgnoreOnIsolate = "yes";
                    DefaultDependencies = "no";
                  };
                  serviceConfig = {
                    Type = "forking";
                    # ExecStart = "${nbd}/bin/nbd-client -nofork -systemd-mark nbd0";
                    Restart = "on-failure";
                    RestartSec = 10;
                  };

                  # wantedBy = [ "initrd-root-device.target" ];
                };
              };
            };
          };
        };

        programs.nbd.enable = true;

        fileSystems = {
          "/" = {
            fsType = "tmpfs";
            options = [ "mode=0755" ];
          };
          "/nix/store" = {
            fsType = "squashfs";
            device = "/dev/nbd0";
            options = [ "x-systemd.requires=nbd.service" ];
          };
        };

        system.build = {
          squashfsStore = pkgs.callPackage "${modulesPath}/../lib/make-squashfs.nix" {
            storeContents = [ config.system.build.toplevel ];
            comp = "zstd";
          };
          netbootScript = pkgs.writeText "boot.ipxe" ''
            #!ipxe
            kernel ${pkgs.stdenv.hostPlatform.linux-kernel.target} init=${config.system.build.toplevel}/init initrd=initrd ifname=et-nbd:''${mac} nbd_server=''${next-server} ${toString config.boot.kernelParams} ''${cmdline}
            initrd initrd
            boot
          '';
          netbootTree = pkgs.linkFarm "netboot-${config.system.name}" [
            {
              name = config.system.boot.loader.kernelFile;
              path = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
            }
            {
              name = "initrd";
              path = "${config.system.build.initialRamdisk}/initrd";
            }
            {
              name = "nix-store.sfs";
              path = config.system.build.squashfsStore;
            }
            {
              name = "boot.ipxe";
              path = config.system.build.netbootScript;
            }
          ];
          netbootArchive = pkgs.runCommand "netboot-${config.system.name}.tar" { } ''
            add() {
              ${pkgs.gnutar}/bin/tar --dereference -rvC "$1" -f "$out" "$2"
            }

            add "${config.system.build.kernel}" "${config.system.boot.loader.kernelFile}"
            add "${config.system.build.initialRamdisk}" initrd

            tmpdir="$(mktemp -d sfsStore.XXXXXX)"
            ln -s "${config.system.build.squashfsStore}" "$tmpdir"/nix-store.sfs
            add "$tmpdir" nix-store.sfs

            add "${config.system.build.netbootScript}" boot.ipxe
          '';
        };
      })
    ];
  };

  mkAsOpt = ext: desc: with lib.types; mkOption {
    type = unspecified;
    default = ext;
    visible = "shallow";
    description = "Configuration as ${desc}.";
  };
in
{
  options = {
    my = {
      build = {
        isDevVM = mkBoolOpt' false "Whether the system is a development VM.";
        allHardware = mkBoolOpt' false
          ("Whether to enable a lot of firmware and kernel modules for a wide range of hardware." +
          "Only applies to some build targets.");
      };

      asDevVM = mkAsOpt asDevVM "a development VM";
      asISO = mkAsOpt asISO "a bootable .iso image";
      asContainer = mkAsOpt asContainer "a container";
      asKexecTree = mkAsOpt asKexecTree "a kexec-able kernel and initrd";
      asNetboot = mkAsOpt asNetboot "a netboot-able kernel initrd, and iPXE script";

      buildAs = options.system.build;
    };

    # Forward declare options that won't exist until the VM module is actually imported
    virtualisation = {
      diskImage = dummyOption;
      forwardPorts = dummyOption;
      sharedDirectories = dummyOption;
      cores = dummyOption;
      memorySize = dummyOption;
      qemu.options = dummyOption;
    };
    isoImage = {
      isoBaseName = dummyOption;
      edition = dummyOption;
      appendToMenuLabel = dummyOption;
    };
  };

  config = {
    virtualisation = {
      diskImage = mkDefault "./.vms/${config.system.name}.qcow2";
    };

    my = {
      buildAs = {
        # The meta.mainProgram should probably be set upstream but oh well...
        devVM = recursiveUpdate config.my.asDevVM.config.system.build.vm { meta.mainProgram = "run-${config.system.name}-vm"; };
        iso = config.my.asISO.config.system.build.isoImage;
        container = config.my.asContainer.config.system.build.toplevel;
        kexecTree = config.my.asKexecTree.config.system.build.kexecTree;
        netbootTree = config.my.asNetboot.config.system.build.netbootTree;
      };
    };
  };

  meta.buildDocsInSandbox = false;
}
