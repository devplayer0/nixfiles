{ lib, inputs, nixfiles, system }:
let
  inherit (builtins) any attrValues filter tryEval;
  inherit (lib) concatMap filterAttrs getName groupBy isDerivation;
  inherit (nixfiles.config) nixos home-manager;

  systems = filter (box: box.system == system) (attrValues nixos.systems);
  homes = filter (home: home.system == system) (attrValues home-manager.homes);

  installedPackages =
    concatMap
      (box:
        let cfg = box.rendered.config;
        in cfg.environment.systemPackages
          ++ concatMap (home: home.home.packages) (attrValues cfg.home-manager.users))
      systems
    ++ concatMap (home: home.configuration.config.home.packages) homes;

  installedByName = groupBy getName installedPackages;
in
filterAttrs
  (_: package:
    # Check names before forcing output paths. Some unrelated upstream exports
    # are helpers or packages that cannot be evaluated on this platform.
    let name = tryEval (if isDerivation package then getName package else null);
    in name.success && name.value != null
      && any (installed: installed.drvPath == package.drvPath)
        (installedByName.${name.value} or [ ]))
  (inputs.llm-agents.packages.${system} or { })
