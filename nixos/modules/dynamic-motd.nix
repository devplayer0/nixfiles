{ lib, pkgs, config, ... }:
let
  inherit (lib) optionalAttrs filterAttrs genAttrs mkIf mkDefault;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.dynamic-motd;

  scriptBin = pkgs.writeShellScript "dynamic-motd-script" cfg.script;
in
{
  options.my.dynamic-motd = with lib.types; {
    enable = mkBoolOpt' true "Whether to enable the dynamic message of the day PAM module.";
    services = mkOpt' (listOf str) [ "login" "sshd" ] "PAM services to enable the dynamic message of the day module for.";
    script = mkOpt' (nullOr lines) null "Script that generates message of the day.";
  };

  config = mkIf (cfg.enable && cfg.script != null) {
    security.pam.services = genAttrs cfg.services (s: {
      text = mkDefault
        ''
          session optional ${pkgs.pam}/lib/security/pam_exec.so stdout quiet ${scriptBin}
        '';
    });
  };

  meta.buildDocsInSandbox = false;
}
