{ lib, pkgs, config, ... }:
  let
    inherit (lib) optionalAttrs filterAttrs genAttrs mkIf mkDefault;
    inherit (lib.my) mkOpt mkBoolOpt;

    cfg = config.my.dynamic-motd;

    scriptBin = pkgs.writeShellScript "dynamic-motd-script" cfg.script;
  in {
    options.my.dynamic-motd = with lib.types; {
      enable = mkBoolOpt true;
      services = mkOpt (listOf str) [ "login" "ssh" ];
      script = mkOpt (nullOr lines) null;
    };

    config = mkIf (cfg.enable && cfg.script != null) {
      security.pam.services = genAttrs cfg.services (s: {
        text = mkDefault
          ''
            session optional ${pkgs.pam}/lib/security/pam_exec.so stdout quiet ${scriptBin}
          '';
      });
    };
  }
