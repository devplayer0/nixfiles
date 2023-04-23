{
  description = "System configs";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "nixpkgs/nixos-22.11";
    nixpkgs-mine.url = "github:devplayer0/nixpkgs/devplayer0";
    nixpkgs-mine-stable.url = "github:devplayer0/nixpkgs/devplayer0-stable";

    home-manager-unstable.url = "home-manager";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";
    home-manager-stable.url = "home-manager/release-22.11";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    # Stuff used by the flake for build / deployment
    ragenix.url = "github:yaxitech/ragenix";
    ragenix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # Stuff used by systems
    impermanence.url = "github:nix-community/impermanence";

    # Packages not in nixpkgs
    sharry.url = "github:eikek/sharry";
    sharry.inputs.nixpkgs.follows = "nixpkgs-unstable";
    borgthin.url = "github:devplayer0/borg";
    borgthin.inputs.nixpkgs.follows = "nixpkgs-mine";
  };

  outputs =
    inputs@{
      self,

      flake-utils,

      nixpkgs-unstable, nixpkgs-stable, nixpkgs-mine, nixpkgs-mine-stable,
      home-manager-unstable, home-manager-stable,

      ...
    }:
    let
      inherit (builtins) mapAttrs;
      inherit (lib) genAttrs recurseIntoAttrs evalModules;
      inherit (lib.flake) flattenTree eachDefaultSystem;
      inherit (lib.my) mkDefaultSystemsPkgs flakePackageOverlay;

      # Extend a lib with extras that _must not_ internally reference private nixpkgs. flake-utils doesn't, but many
      # other flakes (e.g. home-manager) probably do internally.
      libOverlay = final: prev: {
        my = import ./lib { lib = final; };
        flake = flake-utils.lib;
      };
      pkgsLibOverlay = final: prev: { lib = prev.lib.extend libOverlay; };
      myPkgsOverlay = final: prev: import ./pkgs { lib = prev.lib; pkgs = prev; };

      # Override the flake-level lib since we're going to use it for non-config specific stuff
      pkgsFlakes = mapAttrs (_: pkgsFlake: pkgsFlake // { lib = pkgsFlake.lib.extend libOverlay; }) {
        unstable = nixpkgs-unstable;
        stable = nixpkgs-stable;
        mine = nixpkgs-mine;
        mine-stable = nixpkgs-mine-stable;
      };
      hmFlakes = rec {
        unstable = home-manager-unstable;
        stable = home-manager-stable;

        # Don't actually have a fork right now...
        mine = unstable;
        mine-stable = stable;
      };

      # Should only be used for platform-independent flake stuff! This should never leak into a NixOS or home-manager
      # config - they'll get their own.
      lib = pkgsFlakes.unstable.lib;

      # pkgs for dev shell etc
      pkgs' = mapAttrs
        (_: path: mkDefaultSystemsPkgs path (system: {
          overlays = [
            pkgsLibOverlay
            myPkgsOverlay
            inputs.devshell.overlay
            inputs.ragenix.overlays.default
            inputs.deploy-rs.overlay
            (flakePackageOverlay inputs.home-manager-unstable system)
          ];
        }))
        pkgsFlakes;

      # Easiest to build the basic pkgs here (with our lib overlay too)
      configPkgs' = mapAttrs
        (_: path: mkDefaultSystemsPkgs path (_: {
          overlays = [
            pkgsLibOverlay
            myPkgsOverlay
          ];
        }))
        pkgsFlakes;

      configs = [
        # Systems
        nixos/installer.nix
        nixos/boxes/colony
        nixos/boxes/tower
        nixos/boxes/castle

        # Homes
        # home-manager/configs/castle.nix
        home-manager/configs/macsimum.nix
      ];

      nixfiles = evalModules {
        modules = [
          {
            _module.args = {
              inherit lib pkgsFlakes hmFlakes inputs;
              pkgs' = configPkgs';
            };

            nixos.secretsPath = ./secrets;
            deploy-rs.deploy.sshOpts = [ "-i" ".keys/deploy.key" ];
          }

          # Not an internal part of the module system apparently, but it doesn't have any dependencies other than lib
          "${pkgsFlakes.unstable}/nixos/modules/misc/assertions.nix"

          ./nixos
          ./home-manager
          ./deploy-rs.nix
        ] ++ configs;
      };
    in
    # Platform independent stuff
    {
      nixpkgs = pkgs';
      inherit lib nixfiles;

      overlays.default = myPkgsOverlay;

      nixosModules = nixfiles.config.nixos.modules;
      homeModules = nixfiles.config.home-manager.modules;

      nixosConfigurations = mapAttrs (_: s: s.configuration) nixfiles.config.nixos.systems;
      homeConfigurations = mapAttrs (_: s: s.configuration) nixfiles.config.home-manager.homes;

      deploy = nixfiles.config.deploy-rs.rendered;

      # TODO: Modularise?
      herculesCI =
      let
        system = n: self.nixosConfigurations."${n}".config.system.build.toplevel;
        container = n: self.nixosConfigurations."${n}".config.my.buildAs.container;
        home = n: self.homeConfigurations."${n}".activationPackage;
      in
      {
        onPush = {
          default.outputs = {
            shell = self.devShells.x86_64-linux.default;
          };
          systems.outputs = {
            colony = system "colony";
            vms = genAttrs [ "estuary" "shill" ] system;
            containers = genAttrs [ "jackflix" "middleman" "chatterbox" ] container;
          };
          homes.outputs = {
            castle = home "dev@castle";
          };
        };
      };
    } //
    (eachDefaultSystem (system:
    let
      pkgs = pkgs'.mine.${system};
      lib = pkgs.lib;

      shell = pkgs.devshell.mkShell ./devshell;
    in
    # Stuff for each platform
    {
      checks = flattenTree {
        homeConfigurations = recurseIntoAttrs (mapAttrs (_: h: h.activationPackage)
          (lib.filterAttrs (_: h: h.config.nixpkgs.system == system) self.homeConfigurations));
        deploy = recurseIntoAttrs (pkgs.deploy-rs.lib.deployChecks self.deploy);
      };

      packages = flattenTree (import ./pkgs { inherit lib pkgs; });

      devShells.default = shell;
      devShell = shell;
    }));
}
