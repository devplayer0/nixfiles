{ lib, pkgs, inputs, config, utils, ... }:
  let
    inherit (builtins) elem;
    inherit (lib) concatStringsSep concatMap concatMapStringsSep mkIf mkDefault mkMerge mkForce mkVMOverride;
    inherit (lib.my) mkOpt mkBoolOpt mkVMOverride' dummyOption;

    cfg = config.my.tmproot;

    showUnsaved =
      ''
        #!${pkgs.python310}/bin/python
        import stat
        import sys
        import os

        ignored = [
          ${concatStringsSep ",\n  " (map (p: "'${p}'") cfg.ignoreUnsaved)}
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
      options = [ "size=${cfg.size}" ];
    };
  in {
    imports = [ inputs.impermanence.nixosModule ];

    options = with lib.types; {
      my.tmproot = {
        enable = mkBoolOpt true;
        persistDir = mkOpt str "/persist";
        size = mkOpt str "2G";
        ignoreUnsaved = mkOpt (listOf str) [];
      };

      # Forward declare options that won't exist until the VM module is actually imported
      virtualisation = {
        diskImage = dummyOption;
      };
    };

    config = mkIf cfg.enable (mkMerge [
      {
        assertions = [
          {
            assertion = config.fileSystems ? "${cfg.persistDir}";
            message = "The 'fileSystems' option does not specify your persistence file system (${cfg.persistDir}).";
          }
          {
            # I mean you probably _could_, but if you're doing tmproot... come on
            assertion = !config.users.mutableUsers;
            message = "users.mutableUsers is incompatible with tmproot";
          }
        ];

        my.tmproot.ignoreUnsaved = [
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
        ];

        environment.systemPackages = [
          (pkgs.writeScriptBin "tmproot-unsaved" showUnsaved)
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
                config.environment.persistence."${cfg.persistDir}".directories}

              waitDevice "$@"
            }

            type waitDevice > /dev/null || (echo "waitDevice is missing!"; fail)
            alias waitDevice=_waitDevice
          '';

        environment.persistence."${cfg.persistDir}" = {
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

        fileSystems."/" = rootDef;

        virtualisation = {
          diskImage = "./.vms/${config.system.name}-persist.qcow2";
        };
      }
      (mkIf config.services.openssh.enable {
        environment.persistence."${cfg.persistDir}".files =
          concatMap (k: [ k.path "${k.path}.pub" ]) config.services.openssh.hostKeys;
      })
      (mkIf config.networking.resolvconf.enable {
        my.tmproot.ignoreUnsaved = [ "/etc/resolv.conf" ];
      })
      (mkIf config.security.doas.enable {
        my.tmproot.ignoreUnsaved = [ "/etc/doas.conf" ];
      })
      (mkIf config.my.boot.isDevVM {
        my.tmproot.ignoreUnsaved = [ "/nix" ];

        fileSystems = mkVMOverride {
          "/" = mkVMOverride' rootDef;
          # Hijack the "root" device for persistence in the VM
          "${cfg.persistDir}" = {
            device = config.virtualisation.bootDevice;
            neededForBoot = true;
          };
        };
      })
    ]);
  }
