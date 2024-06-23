{ lib, pkgs, config, systems, ... }:
let
  inherit (lib) mkMerge mkIf mkForce mkOption;
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
in
{
  options.my.netboot = with lib.types; {
    client = {
      enable = mkBoolOpt' false "Whether network booting should be enabled.";
    };
    server = {
      enable = mkBoolOpt' false "Whether a netboot server should be enabled.";
      ip = mkOpt' str null "IP clients should connect to via TFTP.";
      host = mkOpt' str config.networking.fqdn "Hostname clients should connect to over HTTP.";
      installer = {
        storeSize = mkOpt' str "16GiB" "Total allowed writable size of store.";
      };
      instances = mkOpt' (listOf str) [ ] "Systems to hold boot files for.";
      keaClientClasses = mkOption {
        type = listOf (attrsOf str);
        description = "Kea client classes for PXE boot.";
        readOnly = true;
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.client.enable {
      # TODO: Implement!
    })
    (mkIf cfg.server.enable {
      environment = {
        etc = {
          "netboot/menu.ipxe".source = menuFile;
          "netboot/shell.efi".source = "${pkgs.edk2-uefi-shell}/shell.efi";
        };
      };

      systemd = {
        services = {
          netboot-update = {
            description = "Update netboot images";
            after = [ "systemd-networkd-wait-online.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
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
      };

      my = {
        tmproot.persistence.config.directories = [
          "/srv/netboot"
          { directory = "/var/cache/netboot"; mode = "0700"; }
        ];
        netboot.server.keaClientClasses = [
          {
            name = "ipxe";
            test = "substring(option[user-class].hex, 0, 4) == 'iPXE'";
            next-server = cfg.server.ip;
            server-hostname = cfg.server.host;
            boot-file-name = "http://${cfg.server.host}/boot.ipxe";
          }
          {
            name = "efi-x86_64";
            test = "option[client-system].hex == 0x0007";
            next-server = cfg.server.ip;
            server-hostname = cfg.server.host;
            boot-file-name = "ipxe-x86_64.efi";
          }
        ];
      };
    })
  ];
}
