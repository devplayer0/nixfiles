{ lib, config, secretsPath, ... }:
let
  inherit (builtins) mapAttrs;
  inherit (lib) mkMerge mkIf;
  inherit (lib.my) mkOpt';

  cfg = config.my.secrets;
in
{
  options.my.secrets = with lib.types; {
    key = mkOpt' (nullOr str) null "Public key that secrets for this system should be encrypted for.";
    files = mkOpt' (attrsOf unspecified) { } "Secrets to decrypt with agenix.";
  };

  config = mkMerge [
    {
      age.secrets = mapAttrs (f: opts: {
        file = "${secretsPath}/${f}.age";
      } // opts) cfg.files;
    }
    (mkIf config.my.build.isDevVM {
      age.identityPaths = [ "/tmp/xchg/dev.key" ];
    })
  ];
}