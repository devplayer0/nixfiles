{ lib, pkgsFlakes, inputs, modules }:
let
  inherit (builtins) attrValues mapAttrs;
  inherit (lib) mkDefault;

  mkSystem =
    name: {
      system,
      nixpkgs ? "unstable",
      config,
    }:
    let
      pkgsFlake = pkgsFlakes.${nixpkgs};
      lib = pkgsFlake.lib;
      # TODO: This is mostly yoinked from nixpkgs/flake.nix master (as of 2022/02/11) since 21.11's version has hacky
      # vm build stuff that breaks our impl. REMOVE WHEN 22.05 IS OUT!
      nixosSystem' = args:
        import "${pkgsFlake}/nixos/lib/eval-config.nix" (args // {
          modules = args.modules ++ [{
            system.nixos.versionSuffix =
              ".${lib.substring 0 8 pkgsFlake.lastModifiedDate}.${pkgsFlake.shortRev}";
            system.nixos.revision = pkgsFlake.rev;
          }];
        });
    in
    nixosSystem' {
      inherit lib system;
      baseModules =
        (import "${pkgsFlake}/nixos/modules/module-list.nix") ++ [
          # Importing modules from module args causes infinite recursion
          inputs.impermanence.nixosModule
          inputs.agenix.nixosModules.age
          inputs.home-manager.nixosModule
        ] ++ modules;
      modules = [
        {
          _module.args = { inherit system inputs; };
          system.name = name;
          networking.hostName = mkDefault name;
        }
        config
      ];
    };
in
mapAttrs mkSystem {
  colony = {
    system = "x86_64-linux";
    nixpkgs = "stable";
    config = boxes/colony.nix;
  };
}
