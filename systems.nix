{ lib, pkgsFlakes, hmFlakes, inputs, pkgs', modules, homeModules }:
let
  inherit (builtins) attrValues mapAttrs;
  inherit (lib) flatten optional optionals mkDefault mkForce;
  inherit (lib.my) homeStateVersion;

  mkSystem =
    name: {
      system,

      nixpkgs ? "unstable",
      home-manager ? nixpkgs,
      hmNixpkgs ? home-manager,

      config,
      # This causes a (very slow) docs rebuild on every change to a module's options it seems
      docCustom ? true,
    }:
    let
      # The flake contains `nixosSystem`, so we do need it (if we didn't have the TODO hacked version anyway)
      pkgsFlake = pkgsFlakes.${nixpkgs};
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

      modules' = [
          # Importing modules from module args causes infinite recursion
          inputs.impermanence.nixosModule
          hmFlake.nixosModule
          inputs.agenix.nixosModules.age
      ] ++ modules;
      pkgs = pkgs'.${nixpkgs}.${system};
      allPkgs = mapAttrs (_: p: p.${system}) pkgs';

      hmFlake = hmFlakes.${home-manager};
    in
    nixosSystem' {
      # Gotta override lib here unforunately, eval-config.nix likes to import its own (unextended) lib. We explicitly
      # don't pass pkgs so that it'll be imported with modularly applied config and overlays.
      lib = pkgs.lib;
      # `baseModules` informs the manual which modules to document
      baseModules =
        (import "${pkgsFlake}/nixos/modules/module-list.nix") ++ (optionals docCustom modules');
      modules = (optionals (!docCustom) modules') ++ [
        (modArgs: {
          warnings = flatten [
            (optional (modArgs.config.home-manager.useGlobalPkgs && (nixpkgs != home-manager))
            ''
              Using global nixpkgs ${nixpkgs} with home-manager ${home-manager} may cause problems.
            '')
          ];

          _module.args = {
            inherit inputs;
            pkgs' = allPkgs;
          };

          system.name = name;
          networking.hostName = mkDefault name;
          nixpkgs = {
            inherit system;
            # Make sure any previously set config / overlays (e.g. lib which will be inherited by home-manager down the
            # line) are passed on when nixpkgs is imported.
            inherit (pkgs) config overlays;
          };

          # Unfortunately it seems there's no way to fully decouple home-manager's lib from NixOS's pkgs.lib. :(
          # https://github.com/nix-community/home-manager/blob/7c2ae0bdd20ddcaafe41ef669226a1df67f8aa06/nixos/default.nix#L22
          home-manager = {
            # Optimise if system and home-manager nixpkgs are the same
            useGlobalPkgs = mkDefault (nixpkgs == home-manager);
            sharedModules = homeModules ++ [
              {
                warnings = flatten [
                  (optional (!modArgs.config.home-manager.useGlobalPkgs && (hmNixpkgs != home-manager))
                  ''
                    Using per-user nixpkgs ${hmNixpkgs} with home-manager ${home-manager} may cause issues.
                  '')
                ];

                # pkgsPath is used by home-manager's nixkpgs module to import nixpkgs (i.e. if !useGlobalPkgs)
                _module.args = {
                  inherit inputs;
                  pkgsPath = toString pkgsFlakes.${hmNixpkgs};
                  pkgs' = allPkgs;
                };
              }
              (homeStateVersion home-manager)
            ];
          };
        })
        config
      ];
    };
in
mapAttrs mkSystem {
  colony = {
    system = "x86_64-linux";
    nixpkgs = "stable";
    home-manager = "unstable";
    config = boxes/colony.nix;
    docCustom = false;
  };
}
