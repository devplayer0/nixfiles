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
    ];
  };

  asNetboot = extendModules {
    modules = flatten [
      allHardware
      ({ pkgs, config, ... }: {
        boot = {
          loader.grub.enable = false;
          initrd = {
            kernelModules = [ "nbd" ];

            systemd = {
              storePaths = with pkgs; [
                gnused
                nbd
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

                networks."10-netboot" = {
                  matchConfig.Name = "et-boot";
                  DHCP = "yes";
                };
              };

              services = {
                nbd = {
                  description = "NBD Root FS";

                  script = ''
                    get_cmdline() {
                      ${pkgs.gnused}/bin/sed -rn "s/^.*$1=(\\S+).*\$/\\1/p" < /proc/cmdline
                    }

                    s="$(get_cmdline nbd_server)"
                    until ${pkgs.netcat}/bin/nc -zv "$s" 22; do
                      sleep 0.1
                    done

                    exec ${pkgs.nbd}/bin/nbd-client -systemd-mark -N "$(get_cmdline nbd_export)" "$s" /dev/nbd0
                  '';
                  unitConfig = {
                    IgnoreOnIsolate = "yes";
                    DefaultDependencies = "no";
                  };
                  serviceConfig = {
                    Type = "forking";
                    Restart = "on-failure";
                    RestartSec = 10;
                  };

                  wantedBy = [ "initrd-root-device.target" ];
                };
              };
            };
          };

          postBootCommands = ''
            # After booting, register the contents of the Nix store
            # in the Nix database in the COW root.
            ${config.nix.package}/bin/nix-store --load-db < /nix-path-registration

            # nixos-rebuild also requires a "system" profile and an
            # /etc/NIXOS tag.
            touch /etc/NIXOS
            ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
          '';
        };

        programs.nbd.enable = true;

        fileSystems = {
          "/" = {
            fsType = "ext4";
            device = "/dev/nbd0";
            noCheck = true;
            autoResize = true;
          };
        };

        networking.useNetworkd = mkForce true;

        systemd = {
          network.networks."10-boot" = {
            matchConfig.Name = "et-boot";
            DHCP = "yes";
            networkConfig.KeepConfiguration = "yes";
          };
        };

        system.build = {
          rootImage = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
            storePaths = [ config.system.build.toplevel ];
            volumeLabel = "netboot-root";
          };
          netbootScript = pkgs.writeText "boot.ipxe" ''
            #!ipxe
            kernel ${pkgs.stdenv.hostPlatform.linux-kernel.target} init=${config.system.build.toplevel}/init initrd=initrd ifname=et-boot:''${mac} nbd_server=''${next-server} ${toString config.boot.kernelParams} ''${cmdline}
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
              name = "rootfs.ext4";
              path = config.system.build.rootImage;
            }
            {
              name = "boot.ipxe";
              path = config.system.build.netbootScript;
            }
          ];
          netbootArchive = pkgs.runCommand "netboot-${config.system.name}.tar.zst" { } ''
            export PATH=${pkgs.zstd}/bin:$PATH
            ${pkgs.gnutar}/bin/tar --dereference --zstd -cvC ${config.system.build.netbootTree} -f "$out" .
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
      volumeID = dummyOption;
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
        netbootArchive = config.my.asNetboot.config.system.build.netbootArchive;
      };
    };
  };

  meta.buildDocsInSandbox = false;
}
