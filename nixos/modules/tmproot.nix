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
      #!${pkgs.python310}/bin/python
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
          ];
          files = [
            "/etc/machine-id"
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
    (mkIf config.security.doas.enable {
      my.tmproot.unsaved.ignore = [ "/etc/doas.conf" ];
    })
    (mkIf config.services.resolved.enable {
      my.tmproot.unsaved.ignore = [ "/etc/resolv.conf" ];
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
        boot.initrd.postDeviceCommands =
          ''
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
      (mkIf config.my.build.isDevVM {
        fileSystems = mkVMOverride {
          # Hijack the "root" device for persistence in the VM
          "${cfg.persistence.dir}" = {
            device = config.virtualisation.bootDevice;
            neededForBoot = true;
          };
        };
      })
    ]))
  ]);

  meta.buildDocsInSandbox = false;
}
