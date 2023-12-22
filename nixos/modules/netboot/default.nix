{ lib, pkgs, config, systems, ... }:
let
  inherit (builtins) toJSON;
  inherit (lib) optional optionalAttrs mapAttrsToList mkMerge mkIf withFeature mkOption;
  inherit (lib.my) mkOpt' mkBoolOpt';

  rpcOpts = with lib.types; {
    options = {
      method = mkOpt' str null "RPC method name.";
      params = mkOpt' (attrsOf unspecified) { } "RPC params";
    };
  };

  cfg = config.my.netboot;
  config' = {
    subsystems = mapAttrsToList (subsystem: c: {
      inherit subsystem;
      config = map (rpc: {
        inherit (rpc) method;
      } // (optionalAttrs (rpc.params != { }) { inherit (rpc) params; })) c;
    }) cfg.config.subsystems;
  };
  configJSON = pkgs.writeText "spdk-config.json" (toJSON config');

  spdk = pkgs.spdk.overrideAttrs (o: {
    configureFlags = o.configureFlags ++ (map (withFeature true) [ "rdma" "ublk" ]);
    buildInputs = o.buildInputs ++ (with pkgs; [ liburing ]);
  });
  spdk-rpc = (pkgs.writeShellScriptBin "spdk-rpc" ''
    exec ${pkgs.python3}/bin/python3 ${spdk.src}/scripts/rpc.py "$@"
  '');
  spdk-setup = (pkgs.writeShellScriptBin "spdk-setup" ''
    exec ${spdk.src}/scripts/setup.sh "$@"
  '');
  spdk-debug = pkgs.writeShellApplication {
    name = "spdk-debug";
    runtimeInputs = [ spdk ];
    text = ''
      set -m
      if [ "$(id -u)" -ne 0 ]; then
        echo "I need to be root!"
        exit 1
      fi

      spdk_tgt ${cfg.extraArgs} --wait-for-rpc &
      until spdk-rpc spdk_get_version > /dev/null; do
        sleep 0.5
      done

      spdk-rpc bdev_set_options --disable-auto-examine
      spdk-rpc framework_start_init

      ${cfg.debugCommands}

      fg %1
    '';
  };

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
      environment.systemPackages = [
        spdk
        spdk-setup
        spdk-rpc
      ] ++ (optional (cfg.debugCommands != "") spdk-debug);

      systemd.services = {
        spdk-tgt = {
          description = "SPDK target";
          path = with pkgs; [
            bash
            python3
            kmod
            gawk
            util-linux
          ];
          serviceConfig = {
            ExecStartPre = "${spdk.src}/scripts/setup.sh";
            ExecStart = "${spdk}/bin/spdk_tgt ${cfg.extraArgs} -c ${configJSON}";
          };
          wantedBy = [ "multi-user.target" ];
        };
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
        services = {
          netboot-update = {
            description = "Update netboot images";
            after = [ "systemd-networkd-wait-online.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = with pkgs; [
              coreutils curl jq gnutar
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
                fname="nixos-installer-devplayer0-netboot-$latestShort.tar"
                downloadUrl="$(curl -s https://git.nul.ie/api/v1/repos/dev/nixfiles/releases/tags/installer | \
                               jq -r ".assets[] | select(.name == \"$fname\").browser_download_url")"
                curl -Lo /tmp/nixos-installer-netboot.tar "$downloadUrl"
                tar -C nixos-installer -xf /tmp/nixos-installer-netboot.tar
                rm /tmp/nixos-installer-netboot.tar
                echo "$latestShort" > nixos-installer/tag.txt
              }

              mkdir -p /srv/netboot
              cd /srv/netboot

              ln -sf ${menuFile} boot.ipxe
              ln -sf "${pkgs.edk2-uefi-shell}/shell.efi"
              update_nixos
            '';
            startAt = "06:00";
            wantedBy = [ "network-online.target" ];
          };

          nbd-server.preStart = ''
            mkdir /tmp/nbdcow
          '';
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
              path = "/srv/netboot/nixos-installer/nix-store.sfs";
              extraOptions = {
                copyonwrite = true;
                cowdir = "/tmp/nbdcow";
                sparse_cow = true;
              };
            };
          };
        };
      };

      my = {
        tmproot.persistence.config.directories = [ "/srv/netboot" ];
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
