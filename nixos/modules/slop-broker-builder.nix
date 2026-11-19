{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf hasPrefix;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.slop-broker-builder;

  user = "slop-broker-build";
  home = "/var/lib/${user}";
  builderConfig = (pkgs.formats.toml { }).generate "slop-broker-builder.toml" {
    inherit (cfg) repository branch;
    key = cfg.keyFile;
    directory = home;
    path = map (p: "${p}/bin") [ pkgs.git config.nix.package pkgs.openssh pkgs.coreutils ];
  };
in
{
  options.my.slop-broker-builder = with lib.types; {
    enable = mkBoolOpt' false "Whether to build commits for `slop-broker` deploys, as `${user}`.";
    package = mkOpt' package pkgs.slop-broker "slop-broker package.";
    repository = mkOpt' str "" "Git repository to fetch commits from.";
    branch = mkOpt' str "master" "Branch that approvals list commits relative to.";
    keyFile = mkOpt' str "" "Runtime path to a read-only key for `repository`, readable by the builder.";
    brokerKeys = mkOpt' (listOf str) [ ] "SSH public keys of brokers that may run builds.";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.repository != "" && hasPrefix "/" cfg.keyFile && !(hasPrefix "/nix/store/" cfg.keyFile);
        message = "slop-broker builder needs a repository and a runtime key file.";
      }
    ];

    # Evaluates and builds agent-written commits, so it holds nothing but a read-only Git key.
    # Brokers' keys can only run one build per connection.
    users = {
      groups.${user} = { };
      users.${user} = {
        isSystemUser = true;
        group = user;
        inherit home;
        createHome = true;
        shell = pkgs.bashInteractive;
        openssh.authorizedKeys.keys = map
          (k: ''restrict,command="${cfg.package}/bin/slop-broker builder --config ${builderConfig}" ${k}'')
          cfg.brokerKeys;
      };
    };
    my.tmproot.persistence.config.directories = [
      {
        directory = home;
        inherit user;
        group = user;
        mode = "0700";
      }
    ];
  };
}
