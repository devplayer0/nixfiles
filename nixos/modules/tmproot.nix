{ lib, pkgs, options, config, ... }:
let
  inherit (lib)
    optionalString concatStringsSep concatMap concatMapStringsSep mkIf mkDefault mkMerge mkForce mkVMOverride
    mkAliasDefinitions;
  inherit (lib.my) mkOpt' mkBoolOpt' mkVMOverride';

  cfg = config.my.tmproot;
  enablePersistence = cfg.persistence.dir != null;

  showUnsaved =
    ''
      #!${pkgs.python3}/bin/python
      import stat
      import sys
      import os

      ignored = [
        ${concatStringsSep ",\n  " (map (p: "'${p}'") cfg.unsaved.ignore)}
      ]

      base = '/'
      base_dev = os.stat(base).st_dev

      def recurse(p, link=None):
        try:
          for ignore in ignored:
            if p.startswith(ignore):
              return

          st = os.lstat(p)
          if st.st_dev != base_dev:
            return

          if stat.S_ISLNK(st.st_mode):
            target = os.path.realpath(p, strict=False)
            if os.access(target, os.F_OK):
              recurse(target, link=p)
              return

            if ${if enablePersistence then "True" else "False"} and target.startswith('${cfg.persistence.dir}'):
              # A symlink whose target cannot be accessed but starts with /persist... almost certaily re-generated on
              # activation
              return
          elif stat.S_ISDIR(st.st_mode):
            for e in os.listdir(p):
              recurse(os.path.join(p, e))
            return

          print(link or p)
        except PermissionError as ex:
          print(f'{p}: {ex.strerror}', file=sys.stderr)

      recurse(base)
    '';

  rootDef = {
    device = "yeet";
    fsType = "tmpfs";
    # The default mode for tmpfs is 777
    options = [ "size=${cfg.size}" "mode=755" ];
  };

  persistSimpleSvc = n: mkIf config.services."${n}".enable {
    my.tmproot.persistence.config.directories = [
      {
        directory = "/var/lib/${n}";
        inherit (config.services."${n}") user group;
      }
    ];
  };
in
{
  options = with lib.types; {
    my.tmproot = {
      enable = mkBoolOpt' true "Whether to enable tmproot.";
      size = mkOpt' str "2G" "Size of tmpfs root";
      persistence = {
        dir = mkOpt' (nullOr str) "/persist" "Path where persisted files are stored.";
        config = mkOpt' options.environment.persistence.type.nestedTypes.elemType { } "Persistence configuration";
      };
      unsaved = {
        showMotd = mkBoolOpt' true "Whether to show unsaved files with `dynamic-motd`.";
        ignore = mkOpt' (listOf str) [ ] "Path prefixes to ignore if unsaved.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          # I mean you probably _could_, but if you're doing tmproot... come on
          assertion = !config.users.mutableUsers;
          message = "users.mutableUsers is incompatible with tmproot";
        }
      ];

      my.tmproot = {
        unsaved.ignore = [
          "/tmp"

          # setup-etc.pl will create this for us
          "/etc/NIXOS"

          # Once mutableUsers is disabled, we should be all clear here
          "/etc/passwd"
          "/etc/group"
          "/etc/shadow"
          "/etc/subuid"
          "/etc/subgid"

          # Lock file for /etc/{passwd,shadow}
          "/etc/.pwd.lock"

          # systemd last updated? I presume they'll get updated on boot...
          "/etc/.updated"
          "/var/.updated"

          # Specifies obsolete files that should be deleted on activation - we'll never have those!
          "/etc/.clean"

          # These are set in environment.etc by the sshd module, but because their mode needs to be changed,
          # setup-etc will copy them instead of symlinking
          "/etc/ssh/authorized_keys.d"

          # Auto-generated (on activation?)
          "/root/.nix-channels"
          "/root/.nix-defexpr"

          "/var/lib/logrotate.status"

          "/etc/cni/net.d/cni.lock"
        ];
        persistence.config = {
          # In impermanence the key in `environment.persistence.*` (aka name passed the attrsOf submodule) sets the
          # default value, so we need to override it when we mkAliasDefinitions
          _module.args.name = mkForce cfg.persistence.dir;

          hideMounts = mkDefault true;
          directories = [
            "/var/log"
            # In theory we'd include only the files needed individually (i.e. the {U,G}ID map files that track deleted
            # users and groups), but `update-users-groups.pl` actually deletes the original files for "atomic update".
            # Also the script runs before impermanence does.
            "/var/lib/nixos"
            "/var/lib/systemd"

            { directory = "/root/.cache/nix"; mode = "0700"; }
          ];
          files = [
            "/etc/machine-id"

            # Just to make sure we get correct default perms
            "/var/lib/.tmproot.dummy"
            "/var/cache/.tmproot.dummy"
          ];
        };
      };

      environment.systemPackages = [
        (pkgs.writeScriptBin "tmproot-unsaved" showUnsaved)
      ];

      my.dynamic-motd.script = mkIf cfg.unsaved.showMotd
        ''
          tmprootUnsaved() {
            local count="$(tmproot-unsaved | wc -l)"
            [ $count -eq 0 ] && return

            echo
            echo -e "\t\e[31;1;4mWarning:\e[0m $count file(s) on / will be lost on shutdown!"
            echo -e '\tTo see them, run `tmproot-unsaved` as root.'
            ${optionalString enablePersistence ''
              echo -e '\tAdd these files to `my.tmproot.persistence.config` to keep them!'
            ''}
            echo -e "\tIf they don't need to be kept, add them to \`my.tmproot.unsaved.ignore\`."
            echo
          }

          tmprootUnsaved
        '';

      fileSystems."/" = rootDef;
    }

    (mkIf config.networking.resolvconf.enable {
      my.tmproot.unsaved.ignore = [ "/etc/resolv.conf" ];
    })
    (mkIf config.networking.nftables.enable {
      my.tmproot.unsaved.ignore = [ "/var/lib/nftables/deletions.nft" ];
    })
    (mkIf config.security.doas.enable {
      my.tmproot.unsaved.ignore = [ "/etc/doas.conf" ];
    })
    (mkIf config.services.resolved.enable {
      my.tmproot.unsaved.ignore = [ "/etc/resolv.conf" ];
    })
    (mkIf config.services.nginx.enable {
      my.tmproot.unsaved.ignore = [ "/var/cache/nginx" ];
    })
    (mkIf config.services.mastodon.enable {
      my.tmproot.unsaved.ignore = [ "/var/lib/mastodon/.secrets_env" ];
    })
    (mkIf config.services.samba.enable {
      my.tmproot.unsaved.ignore = [ "/var/cache/samba" ];
    })
    (mkIf config.my.build.isDevVM {
      my.tmproot.unsaved.ignore = [ "/nix" ];

      fileSystems = mkVMOverride {
        "/" = mkVMOverride' rootDef;
      };
    })

    (mkIf enablePersistence (mkMerge [
      {
        assertions = [
          {
            assertion = (config.fileSystems ? "${cfg.persistence.dir}") || config.boot.isContainer;
            message = "The 'fileSystems' option does not specify your persistence file system (${cfg.persistence.dir}).";
          }
        ];

        # Catch non-existent source directories that are needed for boot (see `pathsNeededForBoot` in
        # nixos/lib/util.nix). We do this by monkey-patching the `waitDevice` function that would otherwise hang.
        # Seems like systemd initrd doesn't care because it uses the systemd.mount units
        # ("If this mount is a bind mount and the specified path does not exist yet it is created as directory.")
        boot.initrd.postDeviceCommands = mkIf (!config.boot.initrd.systemd.enable) ''
            ensurePersistSource() {
              [ -e "/mnt-root$1" ] && return
              echo "Persistent source directory $1 does not exist, creating..."
              install -dm "$2" "/mnt-root$1" || fail
            }

            _waitDevice() {
              local device="$1"

              ${concatMapStringsSep " || \\\n  " (d:
                let
                  sourceDir = "${d.persistentStoragePath}${d.directory}";
                in
                  ''([ "$device" = "/mnt-root${sourceDir}" ] && ensurePersistSource "${sourceDir}" "${d.mode}")'')
                cfg.persistence.config.directories}

              waitDevice "$@"
            }

            type waitDevice > /dev/null || (echo "waitDevice is missing!"; fail)
            alias waitDevice=_waitDevice
          '';

        environment.persistence."${cfg.persistence.dir}" = mkAliasDefinitions options.my.tmproot.persistence.config;

        virtualisation = {
          diskImage = "./.vms/${config.system.name}-persist.qcow2";
        };
      }
      (mkIf config.services.openssh.enable {
        my.tmproot.persistence.config.files =
          concatMap (k: [ k.path "${k.path}.pub" ]) config.services.openssh.hostKeys;
      })
      (mkIf config.services.lvm.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/etc/lvm/archive";
            mode = "0700";
          }
          {
            directory = "/etc/lvm/backup";
            mode = "0700";
          }
        ];
      })
      (mkIf (config.security.acme.certs != { }) {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/lib/acme";
            mode = "0750";
            user = "acme";
            group = "acme";
          }
        ];
      })
      (mkIf config.services.postgresql.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/lib/postgresql";
            mode = "0750";
            user = "postgres";
            group = "postgres";
          }
        ];
      })
      (mkIf config.services.matrix-synapse.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = config.services.matrix-synapse.dataDir;
            user = "matrix-synapse";
            group = "matrix-synapse";
          }
        ];
      })
      (mkIf config.services.jellyfin.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/lib/jellyfin";
            inherit (config.services.jellyfin) user group;
          }
          {
            directory = "/var/cache/jellyfin";
            inherit (config.services.jellyfin) user group;
          }
        ];
      })
      (mkIf config.services.netdata.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/lib/netdata";
            inherit (config.services.netdata) user group;
          }
          {
            directory = "/var/cache/netdata";
            inherit (config.services.netdata) user group;
          }
        ];
      })
      (mkIf config.services.hercules-ci-agent.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = config.services.hercules-ci-agent.settings.baseDirectory;
            mode = "0750";
            user = "hercules-ci-agent";
            group = "hercules-ci-agent";
          }
        ];
      })
      (persistSimpleSvc "transmission")
      (persistSimpleSvc "jackett")
      (persistSimpleSvc "radarr")
      (persistSimpleSvc "sonarr")
      (mkIf config.services.jellyseerr.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/lib/jellyseerr";
            mode = "0750";
            user = "jellyseerr";
            group = "jellyseerr";
          }
        ];
      })
      (mkIf config.services.minio.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = config.services.minio.configDir;
            user = "minio";
            group = "minio";
          }
        ];
      })
      (mkIf config.services.heisenbridge.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/lib/heisenbridge";
            user = "heisenbridge";
            group = "heisenbridge";
          }
        ];
      })
      (mkIf config.virtualisation.podman.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/cache/containers";
            mode = "750";
          }
          "/var/lib/cni"
        ];
      })
      (mkIf config.networking.networkmanager.enable {
        my.tmproot.persistence.config.directories = [
          "/var/lib/NetworkManager"
          "/etc/NetworkManager/system-connections"
        ];
      })
      (mkIf config.services.fprintd.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/lib/fprint";
            mode = "700";
          }
        ];
      })
      (mkIf config.hardware.bluetooth.enable {
        my.tmproot.persistence.config.directories = [ "/var/lib/bluetooth" ];
      })
      (mkIf config.services.blueman.enable {
        my.tmproot.persistence.config.directories = [ "/var/lib/blueman" ];
      })
      (mkIf config.my.build.isDevVM {
        fileSystems = mkVMOverride {
          # Hijack the "root" device for persistence in the VM
          "${cfg.persistence.dir}" = {
            device = config.virtualisation.bootDevice;
            neededForBoot = true;
          };
        };
      })
      (mkIf config.services.mastodon.enable {
        my.tmproot.persistence.config.directories = with config.services.mastodon; [
          {
            directory = "/var/lib/mastodon/public-system";
            inherit user group;
          }
          {
            directory = "/var/lib/redis-mastodon";
            mode = "700";
            user = "redis-mastodon";
            group = "redis-mastodon";
          }
        ];
      })
      (mkIf config.services.hardware.bolt.enable {
        my.tmproot.persistence.config.directories = [ "/var/lib/boltd" ];
      })
      (mkIf config.boot.plymouth.enable {
        my.tmproot.persistence.config.files = [ "/var/lib/plymouth/boot-duration" ];
      })
      (mkIf config.services.nextcloud.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = config.services.nextcloud.home;
            mode = "0750";
            user = "nextcloud";
            group = "nextcloud";
          }
        ];
      })
      (mkIf config.services.minecraft-server.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = config.services.minecraft-server.dataDir;
            mode = "0750";
            user = "minecraft";
            group = "minecraft";
          }
        ];
      })
      (mkIf config.services.samba.enable {
        my.tmproot.persistence.config.directories = [
          "/var/lib/samba"
        ];
      })
      (mkIf config.hardware.rasdaemon.enable {
        my.tmproot.persistence.config.directories = [ "/var/lib/rasdaemon" ];
      })
      (mkIf (config.services.gitea-actions-runner.instances != { }) {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/lib/gitea-runner";
            mode = "0750";
            user = "gitea-runner";
            group = "gitea-runner";
          }
        ];
      })
      (mkIf config.virtualisation.libvirtd.enable {
        my.tmproot.persistence.config.directories = [ "/var/lib/libvirt" ];
      })
      (mkIf (with config.services.kea; (dhcp4.enable || dhcp6.enable || dhcp-ddns.enable)) {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/lib/kea";
            mode = "0750";
            user = "kea";
            group = "kea";
          }
        ];
      })
      (persistSimpleSvc "headscale")
      (mkIf config.services.tailscale.enable {
        my.tmproot.persistence.config.directories = [ "/var/lib/tailscale" ];
      })
      (mkIf config.my.librespeed.backend.enable {
        my.tmproot.persistence.config.directories = [ "/var/lib/librespeed-go" ];
      })
      (mkIf config.services.hedgedoc.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/lib/hedgedoc";
            user = "hedgedoc";
            group = "hedgedoc";
          }
        ];
      })
      (mkIf config.services.wastebin.enable {
        my.tmproot.persistence.config.directories = [ "/var/lib/private/wastebin" ];
      })
      (mkIf config.services.photoprism.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = config.services.photoprism.storagePath;
            mode = "0750";
            user = "photoprism";
            group = "photoprism";
          }
        ];
      })
      (mkIf config.services.mautrix-whatsapp.enable {
        my.tmproot.persistence.config.directories = [
          {
            directory = "/var/lib/mautrix-whatsapp";
            mode = "0750";
            user = "mautrix-whatsapp";
            group = "mautrix-whatsapp";
          }
        ];
      })
    ]))
  ]);

  meta.buildDocsInSandbox = false;
}
