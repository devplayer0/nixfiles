{ lib, hmFlakes, inputs, pkgs', modules }:
let
  inherit (builtins) removeAttrs mapAttrs;
  inherit (lib) flatten optional recursiveUpdate;
  inherit (lib.my) homeStateVersion;

  mkHome = name: {
    system,
    nixpkgs ? "unstable",
    home-manager ? nixpkgs,
    config,
    ...
  }@args:
  let
    rest = removeAttrs args [ "nixpkgs" "home-manager" "config" ];
  in
  # homeManagerConfiguration doesn't allow us to set lib directly (inherits from passed pkgs)
  hmFlakes.${home-manager}.lib.homeManagerConfiguration (recursiveUpdate rest {
    configuration = config;
    # Passing pkgs here doesn't set the global pkgs, just where it'll be imported from (and where the global lib is
    # derived from). We want home-manager to import pkgs itself so it'll apply config and overlays modularly. Any config
    # and overlays previously applied will be passed on by `homeManagerConfiguration` though.
    pkgs = pkgs'.${nixpkgs}.${system};
    extraModules = modules ++ [
      {
        warnings = flatten [
          (optional (nixpkgs != home-manager)
          ''
            Using nixpkgs ${nixpkgs} with home-manager ${home-manager} may cause issues.
          '')
        ];

        _module.args = {
          inherit inputs;
          pkgs' = mapAttrs (_: p: p.${system}) pkgs';
        };
      }
      (homeStateVersion home-manager)
    ];
  });
in
mapAttrs mkHome {
  "dev@castle" = {
    system = "x86_64-linux";
    nixpkgs = "unstable";
    config = homes/castle.nix;

    homeDirectory = "/home/dev";
    username = "dev";
  };
}
