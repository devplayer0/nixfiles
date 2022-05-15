{ lib, pkgs, config, secretsPath, ... }:
let
  inherit (builtins) mapAttrs;
  inherit (lib) mkMerge mkIf;
  inherit (lib.my) mkOpt';

  cfg = config.my.secrets;
in
{
  options.my.secrets = with lib.types; {
    vmKeyPath = mkOpt' str "/tmp/xchg/dev.key" "Path to dev key when in a dev VM.";
    key = mkOpt' (nullOr str) null "Public key that secrets for this system should be encrypted for.";
    files = mkOpt' (attrsOf unspecified) { } "Secrets to decrypt with agenix.";
  };

  config = mkMerge [
    {
      age = {
        secrets = mapAttrs (f: opts: {
          file = "${secretsPath}/${f}.age";
        } // opts) cfg.files;
        # agenix sets this as a default but adding any custom extras will _replace_ the list (different priority)
        identityPaths =
          mkIf config.services.openssh.enable
          (map
            # Use the persit dir to grab the keys instead, otherwise they might not be ready. We can't really make
            # agenix depend on impermanence, since users depends on agenix (to decrypt passwords) and impermanence
            # depends on users
            (e: let pDir = config.my.tmproot.persistence.dir; in if pDir != null then "${pDir}/${e.path}" else e.path)
            (lib.filter (e: e.type == "rsa" || e.type == "ed25519") config.services.openssh.hostKeys));
      };
    }
    (mkIf config.my.build.isDevVM {
      age.identityPaths = [ cfg.vmKeyPath ];
    })
  ];
}
