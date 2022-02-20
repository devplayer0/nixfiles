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

        autoRollback = true;
        magicRollback = true;
      };

      # Filter out null values so deploy merges overriding options correctly
      rendered = lib.my.deploy-rs.filterOpts cfg.deploy;
    };
  };
}
