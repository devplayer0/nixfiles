{ lib, pkgsFlakes, inputs, modules }:
  let
    inherit (builtins) attrValues mapAttrs;
    inherit (lib) mkDefault;

    mkSystem = name: {
      system,
      nixpkgs ? "unstable",
      config,
    }:
      let
        lib = pkgsFlakes.${nixpkgs}.lib;
      in lib.nixosSystem {
        inherit lib system;
        specialArgs = { inherit inputs; myModules = modules; };
        modules = attrValues modules ++ [ { networking.hostName = mkDefault name; } config  ];
      };
  in mapAttrs mkSystem {
    colony = {
      system = "x86_64-linux";
      nixpkgs = "stable";
      config = boxes/colony.nix;
    };
  }
