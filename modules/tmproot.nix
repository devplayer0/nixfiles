{ lib, pkgs, inputs, config, ... }@args:
  let
    inherit (lib) any concatStringsSep mkIf mkDefault mkMerge mkVMOverride;
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
    imports = [ inputs.impermanence.nixosModules.impermanence ];

    options.my.tmproot = with lib.types; {
      enable = mkBoolOpt true;
      persistDir = mkOpt str "/persist";
      size = mkOpt str "2G";
      ignoreUnsaved = mkOpt (listOf str) [
        "/tmp"
      ];
    };

    # Forward declare options that won't exist until the VM module is actually imported
    options.virtualisation = {
      diskImage = dummyOption;
    };

    config = mkMerge [
      (mkIf cfg.enable {
        assertions = [
          {
            assertion = config.fileSystems ? "${cfg.persistDir}";
            message = "The 'fileSystems' option does not specify your persistence file system (${cfg.persistDir}).";
          }
        ];

        environment.systemPackages = [
          (pkgs.writeScriptBin "tmproot-unsaved" showUnsaved)
        ];

        environment.persistence."${cfg.persistDir}" = {
          hideMounts = mkDefault true;
          directories = [
            "/var/log"
          ];
          files = [
            "/etc/machine-id"
          ];
        };

        fileSystems."/" = rootDef;

        virtualisation = {
          diskImage = "./.vms/${config.system.name}-persist.qcow2";
        };
      })
      (mkIf (cfg.enable && config.my.boot.isDevVM) {
        fileSystems = mkVMOverride {
          "/" = mkVMOverride' rootDef;
          # Hijack the "root" device for persistence in the VM
          "${cfg.persistDir}" = {
            device = config.virtualisation.bootDevice;
            neededForBoot = true;
          };
        };
      })
    ];
  }
