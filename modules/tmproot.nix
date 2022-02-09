{ lib, pkgs, inputs, config, ... }:
  let
    inherit (lib) concatStringsSep mkIf mkDefault mkAliasDefinitions;
    inherit (lib.my) mkOpt mkBoolOpt;

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
  in {
    options.my.tmproot = with lib.types; {
      enable = mkBoolOpt true;
      ignoreUnsaved = mkOpt (listOf str) [
        "/tmp"
      ];
    };

    config = mkIf cfg.enable {
      environment.systemPackages = [
        (pkgs.writeScriptBin "tmproot-unsaved" showUnsaved)
      ];
    };
  }
