{ lib, pkgs, config, ... }:
let
  inherit (lib) mkMerge mkIf mkForce genAttrs concatMapStringsSep;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.netboot;

  tftpRoot = pkgs.linkFarm "tftp-root" [
    {
      name = "ipxe-x86_64.efi";
      path = "${pkgs.ipxe}/ipxe.efi";
    }
  ];
  menuFile = pkgs.runCommand "menu.ipxe" {
    bootHost = cfg.server.host;
  } ''
    substituteAll ${./menu.ipxe} "$out"
  '';

  bootBuilder = pkgs.substituteAll {
    src = ./netboot-loader-builder.py;
    isExecutable = true;

    inherit (pkgs) python3;
    bootspecTools = pkgs.bootspec;
    nix = config.nix.package.out;

    inherit (config.system.nixos) distroName;
    systemName = config.system.name;
    inherit (cfg.client) configurationLimit;
    checkMountpoints = pkgs.writeShellScript "check-mountpoints" ''
      if ! ${pkgs.util-linuxMinimal}/bin/findmnt /boot > /dev/null; then
        echo "/boot is not a mounted partition. Is the path configured correctly?" >&2
        exit 1
      fi
    '';
  };
in
{
  options.my.netboot = with lib.types; {
    client = {
      enable = mkBoolOpt' false "Whether network booting should be enabled.";
      configurationLimit = mkOpt' ints.unsigned 10 "Max generations to show in boot menu.";
    };
    server = {
      enable = mkBoolOpt' false "Whether a netboot server should be enabled.";
      ip = mkOpt' str null "IP clients should connect to via TFTP.";
      host = mkOpt' str config.networking.fqdn "Hostname clients should connect to over HTTP / NFS.";
      allowedPrefixes = mkOpt' (listOf str) null "Prefixes clients should be allowed to connect from (NFS).";
      installer = {
        storeSize = mkOpt' str "16GiB" "Total allowed writable size of store.";
      };
      instances = mkOpt' (listOf str) [ ] "Systems to hold boot files for.";
    };
  };

  config = mkMerge [
    (mkIf cfg.client.enable {
      systemd = {
        services = {
          mount-boot = {
            description = "Mount /boot";
            after = [ "systemd-networkd-wait-online.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = with pkgs; [ gnused ldns nfs-utils ];
            script = ''
              get_cmdline() {
                sed -rn "s/^.*$1=(\\S+).*\$/\\1/p" < /proc/cmdline
              }

              host="$(get_cmdline boothost)"
              if [ -z "$host" ]; then
                echo "boothost kernel parameter not found!" >&2
                exit 1
              fi

              until [ -n "$(drill -Q $host)" ]; do
                sleep 0.1
              done

              mkdir -p /boot
              mount.nfs $host:/srv/netboot/systems/${config.system.name} /boot
            '';

            wantedBy = [ "remote-fs.target" ];
          };
        };
      };

      boot.supportedFilesystems.nfs = true;
      boot.loader = {
        grub.enable = false;
        systemd-boot.enable = false;
      };
      system = {
        build.installBootLoader = bootBuilder;
        boot.loader.id = "ipxe-netboot";
      };
    })
    (mkIf cfg.server.enable {
      environment = {
        etc = {
          "netboot/menu.ipxe".source = menuFile;
          "netboot/shell.efi".source = "${pkgs.edk2-uefi-shell}/shell.efi";
        };
      };

      systemd = {
        tmpfiles.settings."10-netboot" = genAttrs
          (map (i: "/srv/netboot/systems/${i}") cfg.server.instances)
          (p: {
            d = {
              user = "root";
              group = "root";
              mode = "0777";
            };
          });

        services = {
          netboot-update = {
            description = "Update netboot images";
            after = [ "systemd-networkd-wait-online.service" ];
            serviceConfig.Type = "oneshot";
            path = with pkgs; [
              coreutils curl jq zstd gnutar
            ];
            script = ''
              update_nixos() {
                latestShort="$(curl -s https://git.nul.ie/api/v1/repos/dev/nixfiles/tags/installer \
                             | jq -r .commit.sha | cut -c -7)"
                if [ -f nixos-installer/tag.txt ] && [ "$(< nixos-installer/tag.txt)" = "$latestShort" ]; then
                  echo "NixOS installer is up to date"
                  return
                fi

                echo "Updating NixOS installer to $latestShort"
                mkdir -p nixos-installer
                fname="jackos-installer-netboot-$latestShort.tar.zst"
                downloadUrl="$(curl -s https://git.nul.ie/api/v1/repos/dev/nixfiles/releases/tags/installer | \
                               jq -r ".assets[] | select(.name == \"$fname\").browser_download_url")"
                curl -Lo /tmp/nixos-installer-netboot.tar.zst "$downloadUrl"
                tar -C nixos-installer --zstd -xf /tmp/nixos-installer-netboot.tar.zst
                truncate -s "${cfg.server.installer.storeSize}" nixos-installer/rootfs.ext4
                rm /tmp/nixos-installer-netboot.tar.zst
                echo "$latestShort" > nixos-installer/tag.txt
              }

              mkdir -p /srv/netboot
              cd /srv/netboot

              ln -sf ${menuFile} boot.ipxe
              ln -sf "${pkgs.edk2-uefi-shell}/shell.efi" "efi-shell-${config.nixpkgs.localSystem.linuxArch}.efi"
              update_nixos
            '';
            startAt = "06:00";
            wantedBy = [ "network-online.target" ];
          };

          nbd-server = {
            serviceConfig = {
              PrivateUsers = mkForce false;
              CacheDirectory = "netboot";
            };
          };
        };
      };

      services = {
        atftpd = {
          enable = true;
          root = tftpRoot;
        };

        nginx = {
          virtualHosts."${cfg.server.host}" = {
            locations."/" = {
              root = "/srv/netboot";
              extraConfig = ''
                autoindex on;
              '';
            };
          };
        };

        nbd.server = {
          enable = true;
          extraOptions = {
            allowlist = true;
          };
          exports = {
            nixos-installer = {
              path = "/srv/netboot/nixos-installer/rootfs.ext4";
              extraOptions = {
                copyonwrite = true;
                cowdir = "/var/cache/netboot";
                sparse_cow = true;
              };
            };
          };
        };

        nfs = {
          server = {
            enable = true;
            exports = ''
              /srv/netboot/systems ${concatMapStringsSep " " (p: "${p}(rw,all_squash)") cfg.server.allowedPrefixes}
            '';
          };
        };
      };

      my = {
        tmproot.persistence.config.directories = [
          "/srv/netboot"
          { directory = "/var/cache/netboot"; mode = "0700"; }
        ];
      };
    })
  ];
}
