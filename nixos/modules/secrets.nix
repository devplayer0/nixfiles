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
          (map (e: e.path) (lib.filter (e: e.type == "rsa" || e.type == "ed25519") config.services.openssh.hostKeys));
      };
    }
    (mkIf (config.age.secrets != { }) {
        system.activationScripts.agenixMountSecrets.deps = mkIf (config.my.tmproot.persistence.dir != null) [
          # The key used to decrypt is not going to exist!
          "persist-files"
        ];
    })
    (mkIf config.my.build.isDevVM {
      age.identityPaths = [ cfg.vmKeyPath ];
    })
  ];
}
