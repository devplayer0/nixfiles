{ lib, config, ... }:
let
  inherit (builtins) replaceStrings attrNames mapAttrs;
  inherit (lib) nameValuePair mapAttrs' intersectLists filterAttrs mkOption;

  cfg = config.deploy-rs;

  systems = config.nixos.systems;
  # deploy can't handle the `@`
  homes = mapAttrs' (n: v: nameValuePair (replaceStrings ["@"] ["-at-"] n) v) config.home-manager.homes;

  nodesFor = systemsOrHomes: filterAttrs (_: m: m != null) (mapAttrs (_: c:
    if c.configuration.config.my.deploy.enable
    # Since we're using the submodule, we need to take the defintions. By importing them, the submodule type checking
    # and merging can still work at this level. Also gotta make the module a function or else it'll just be treated as
    # configuration only (aka shorthandOnlyDefinesConfig = true)
    then { ... }: { imports = c.configuration.options.my.deploy.node.definitions; }
    else null
  ) systemsOrHomes);
in
{
  options.deploy-rs = with lib.types; {
    inherit (lib.my.deploy-rs) deploy;
    rendered = mkOption {
      type = attrsOf unspecified;
      default = null;
      internal = true;
      description = "Rendered deploy-rs configuration.";
    };
    sshConnections = mkOption {
      type = attrsOf unspecified;
      internal = true;
      description = "SSH connection settings and container names for ssh-machine.";
    };
  };

  config = {
    assertions = [
      (let
        duplicates = intersectLists (attrNames systems) (attrNames homes);
      in
      {
        assertion = duplicates == [ ];
        message = "Duplicate-ly named NixOS systems: ${toString duplicates}";
      })
    ];

    deploy-rs = {
      deploy = {
        nodes = (
          (nodesFor systems) //
          (nodesFor homes)
        );

        autoRollback = false;
        magicRollback = false;
      };

      # Filter out null values so deploy merges overriding options correctly
      rendered = lib.my.deploy-rs.filterOpts cfg.deploy;

      sshConnections = mapAttrs (name: node:
      let
        system = systems.${name}.configuration.config or null;
        hostnames = if system == null then [ ] else system.my.deploy.sshHostnames;
        instances = if system == null then { } else system.my.containers.instances;
      in
      {
        inherit (node) sshUser;
        sshOpts = cfg.rendered.sshOpts ++ node.sshOpts;
        hostnames = if hostnames == [ ] then [ node.hostname ] else hostnames;
        containers = attrNames instances;
        sudo = node.sudo or (cfg.rendered.sudo or "sudo -u");
      }) cfg.rendered.nodes;
    };
  };
}
