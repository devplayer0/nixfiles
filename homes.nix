{ lib, inputs, pkgs', modules }:
let
  inherit (builtins) removeAttrs mapAttrs;
  inherit (lib) recursiveUpdate;

  mkHome = name: {
    system,
    nixpkgs ? "unstable",
    config,
    ...
  }@args:
  let
    rest = removeAttrs args [ "nixpkgs" "config" ];
  in
  inputs.home-manager.lib.homeManagerConfiguration (recursiveUpdate rest {
    configuration = config;
    pkgs = pkgs'.${nixpkgs}.${system};
    extraModules = modules ++ [{
      _module.args = { inherit inputs; isStandalone = true; };
    }];
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
