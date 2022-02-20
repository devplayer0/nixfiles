{ lib, hmFlakes, inputs, pkgs', config, ... }:
let
  inherit (builtins) head tail mapAttrs attrValues;
  inherit (lib) flatten optional mkOption mkOptionType;
  inherit (lib.my) homeStateVersion mkOpt' commonOpts inlineModule';

  cfg = config.home-manager;

  mkHome = {
    config',
    defs,
  }:
  # homeManagerConfiguration doesn't allow us to set lib directly (inherits from passed pkgs)
  hmFlakes.${config'.home-manager}.lib.homeManagerConfiguration {
    inherit (config') system homeDirectory username;
    # Pull the first def as `configuration` and add any others to `extraModules` (they should end up in the same list
    # of modules to evaluate anyway)
    configuration = head defs;
    # Passing pkgs here doesn't set the global pkgs, just where it'll be imported from (and where the global lib is
    # derived from). We want home-manager to import pkgs itself so it'll apply config and overlays modularly. Any config
    # and overlays previously applied will be passed on by `homeManagerConfiguration` though.
    pkgs = pkgs'.${config'.nixpkgs}.${config'.system};
    extraSpecialArgs = { inherit inputs; };
    extraModules = (attrValues cfg.modules) ++ [
      {
        warnings = flatten [
          (optional (config'.nixpkgs != config'.home-manager)
          ''
            Using nixpkgs ${config'.nixpkgs} with home-manager ${config'.home-manager} may cause issues.
          '')
        ];

        _module.args = {
          pkgs' = mapAttrs (_: p: p.${config'.system}) pkgs';
        };
      }
      (homeStateVersion config'.home-manager)
    ] ++ (tail defs);
  };

  homeOpts = with lib.types; { config, ... }: {
    options = {
      inherit (commonOpts) system nixpkgs home-manager;
      # TODO: docCustom for home-manager?
      homeDirectory = mkOpt' str null "Absolute path to home directory.";
      username = mkOpt' str null "Username for the configuration.";

      configuration = mkOption {
        description = "home-manager configuration module.";
        type = mkOptionType {
          name = "home-manager configuration";
          merge = _: defs: mkHome {
            config' = config;
            defs = map (d: inlineModule' d.file d.value) defs;
          };
        };
      };
    };
  };
in
{
  imports = [ modules/_list.nix ];
  options = with lib.types; {
    home-manager = {
      modules = mkOpt' (attrsOf commonOpts.moduleType) { } "home-manager modules to be exported by nixfiles.";
      homes = mkOpt' (attrsOf (submodule homeOpts)) { } "home-manager configurations to be exported by nixfiles.";
    };
  };
}
