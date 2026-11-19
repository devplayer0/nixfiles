{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf mkMerge optionalAttrs;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.slop;

  # Each job gets its own `Host` alias, so the right key is used even with both on one box
  hostBlock = keyFile: {
    hostname = cfg.host;
    user = "slop";
    identityFile = keyFile;
    identitiesOnly = true;
    extraOptions.IdentityAgent = "none";
  };

  # Read by every `slop` and `slop-approve`, installed or from the nixfiles devshell, so a switch
  # reaches every shell at once; `SLOP_BROKER` and `SLOP_APPROVE` still override it.
  clientConfig = (pkgs.formats.toml { }).generate "slop-config.toml" (
    optionalAttrs cfg.request.enable { broker = "ssh:slop-request"; } //
    optionalAttrs cfg.approve.enable { approve = "ssh:slop-approve"; }
  );

  jobOpts = what: with lib.types; {
    enable = mkBoolOpt' false "Whether to ${what} over SSH.";
    keyFile = mkOpt' str "" "SSH private key for this job, configured for it in `my.slop-broker` on the broker's box.";
  };
in
{
  options.my.slop = with lib.types; {
    host = mkOpt' str "palace.h.nul.ie" "Box running `slop-broker`.";
    request = jobOpts "send requests with `slop`";
    approve = jobOpts "answer requests with `slop-approve`";
  };

  config = mkMerge [
    (mkIf (cfg.request.enable || cfg.approve.enable) {
      assertions = [
        {
          assertion = cfg.request.enable -> cfg.request.keyFile != "";
          message = "my.slop.request needs a key file.";
        }
        {
          assertion = cfg.approve.enable -> cfg.approve.keyFile != "";
          message = "my.slop.approve needs a key file.";
        }
      ];

      home.packages = [ pkgs.slop-broker ];
      xdg.configFile."slop/config.toml".source = clientConfig;
      programs.ssh.enable = true;
    })
    (mkIf cfg.request.enable {
      programs.ssh.matchBlocks.slop-request = hostBlock cfg.request.keyFile;
    })
    (mkIf cfg.approve.enable {
      programs.ssh.matchBlocks.slop-approve = hostBlock cfg.approve.keyFile;
    })
  ];
}
