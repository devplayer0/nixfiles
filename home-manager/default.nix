{ lib, hmFlakes, pkgsFlakes, inputs, pkgs', config, ... }:
let
  inherit (builtins) head tail mapAttrs attrValues;
  inherit (lib) flatten optional optionalAttrs mkOption mkDefault mkOptionType mkIf;
  inherit (lib.my) homeStateVersion' homeStateVersion mkOpt' commonOpts inlineModule' applyAssertions;

  cfg = config.home-manager;

  mkHome = {
    config',
    defs,
  }:
  let
    # TODO: Remove this backwards compatibility when 22.11 becomes stable
    # https://github.com/nix-community/home-manager/blob/master/docs/release-notes/rl-2211.adoc
    newCfgFn = (homeStateVersion' config'.home-manager) == "22.11";
    modArg = if newCfgFn then "modules" else "extraModules";
  in
  # homeManagerConfiguration doesn't allow us to set lib directly (inherits from passed pkgs)
  hmFlakes.${config'.home-manager}.lib.homeManagerConfiguration ({
    # Passing pkgs here doesn't set the global pkgs, just where it'll be imported from (and where the global lib is
    # derived from). We want home-manager to import pkgs itself so it'll apply config and overlays modularly. Any config
    # and overlays previously applied will be passed on by `homeManagerConfiguration` though. In fact, because of weird
    # config merging behaviour (or lack thereof; similar to NixOS module), we explicitly pass empty config.
    # TODO: Check if this is fixed in future.
    pkgs = pkgs'.${config'.nixpkgs}.${config'.system} // { config = { }; };
    extraSpecialArgs = { inherit inputs pkgsFlakes; pkgsFlake = pkgsFlakes.${config'.nixpkgs}; };
    "${modArg}" = (attrValues cfg.modules) ++ [
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

        home = mkIf newCfgFn {
          inherit (config') homeDirectory username;
        };
      }
      (homeStateVersion config'.home-manager)
    ] ++ (if newCfgFn then defs else tail defs);
  } // (optionalAttrs (!newCfgFn) {
    inherit (config') system homeDirectory username;

    # Pull the first def as `configuration` and add any others to `extraModules` for the old style config (they should
    # end up in the same list of modules to evaluate anyway)
    configuration = head defs;
  }));

  homeOpts = with lib.types; { ... }@args:
  let
    config' = args.config;
  in
  {
    options = {
      inherit (commonOpts) system nixpkgs home-manager;
      # TODO: docCustom for home-manager?
      # Not possible I think, the doc generation code only ever includes its own modules...
      # (https://github.com/nix-community/home-manager/blob/0232fe1b75e6d7864fd82b5c72f6646f87838fc3/docs/default.nix#L37)
      homeDirectory = mkOpt' str null "Absolute path to home directory.";
      username = mkOpt' str null "Username for the configuration.";

      configuration = mkOption {
        description = "home-manager configuration module.";
        type = mkOptionType {
          name = "home-manager configuration";
          merge = _: defs: applyAssertions config (mkHome {
            inherit config';
            defs = map (d: inlineModule' d.file d.value) defs;
          });
        };
      };
    };

    config = {
      nixpkgs = mkDefault config'.home-manager;
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
