{
  description = "System configs";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "nixpkgs/nixos-24.05";
    nixpkgs-mine.url = "github:devplayer0/nixpkgs/devplayer0";
    nixpkgs-mine-stable.url = "github:devplayer0/nixpkgs/devplayer0-stable";

    home-manager-unstable.url = "home-manager";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";
    home-manager-stable.url = "home-manager/release-24.05";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    # Stuff used by the flake for build / deployment
    # ragenix.url = "github:yaxitech/ragenix";
    ragenix.url = "github:devplayer0/ragenix/add-rekey-one-flag";
    ragenix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # Stuff used by systems
    impermanence.url = "github:nix-community/impermanence";
    boardie.url = "git+https://git.nul.ie/dev/boardie";
    boardie.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nixGL.url = "github:nix-community/nixGL";
    nixGL.inputs.nixpkgs.follows = "nixpkgs-unstable";

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
      inherit (builtins) mapAttrs replaceStrings elem;
      inherit (lib) mapAttrs' filterAttrs nameValuePair recurseIntoAttrs evalModules;
      inherit (lib.flake) flattenTree eachDefaultSystem;
      inherit (lib.my) mkDefaultSystemsPkgs flakePackageOverlay;

      # Extend a lib with extras that _must not_ internally reference private nixpkgs. flake-utils doesn't, but many
      # other flakes (e.g. home-manager) probably do internally.
      libOverlay = final: prev: {
        my = import ./lib { lib = final; };
        flake = flake-utils.lib;
      };
      pkgsLibOverlay = final: prev: { lib = prev.lib.extend libOverlay; };
      myPkgsOverlay = final: prev: import ./pkgs { lib = final.lib; pkgs = prev; };

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
            inputs.devshell.overlays.default
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

          config = {
            # RMS forgive me...
            # Normally this is set modularly, but sometimes we need to use other pkgs
            allowUnfreePredicate = p: elem (lib.getName p) [
              "widevine-cdm"
              "chromium-unwrapped"
              "chromium"
            ];
          };
        }))
        pkgsFlakes;

      configs = [
        # Systems
        nixos/installer.nix
        nixos/boxes/colony
        nixos/boxes/tower
        nixos/boxes/home/stream.nix
        nixos/boxes/home/palace
        nixos/boxes/home/castle
        nixos/boxes/britway
        nixos/boxes/kelder

        # Homes
        # home-manager/configs/macsimum.nix
      ];

      nixfiles = evalModules {
        modules = [
          {
            _module.args = {
              inherit lib pkgsFlakes hmFlakes self inputs;
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

      nixosConfigurations = mapAttrs (_: s: s.rendered) nixfiles.config.nixos.systems;
      homeConfigurations = mapAttrs (_: s: s.configuration) nixfiles.config.home-manager.homes;

      deploy = nixfiles.config.deploy-rs.rendered;
    } //
    (eachDefaultSystem (system:
    let
      pkgs = pkgs'.mine.${system};
      lib = pkgs.lib;

      filterSystem = filterAttrs (_: c: c.config.nixpkgs.system == system);
      homes =
        mapAttrs
          (_: h: h.activationPackage)
          (filterSystem self.homeConfigurations);
      systems =
        mapAttrs
          (_: h: h.config.system.build.toplevel)
          (filterSystem self.nixosConfigurations);
      shell = pkgs.devshell.mkShell ./devshell;
    in
    # Stuff for each platform
    rec {
      checks = flattenTree {
        homeConfigurations = recurseIntoAttrs homes;
        deploy = recurseIntoAttrs (pkgs.deploy-rs.lib.deployChecks self.deploy);
      };

      packages = flattenTree (import ./pkgs { inherit lib pkgs; });

      devShells.default = shell;

      ci =
      let
        homes' =
          mapAttrs'
            (n: v: nameValuePair ''home-${replaceStrings ["@"] ["-at-"] n}'' v)
            homes;
        systems' = mapAttrs' (n: v: nameValuePair "system-${n}" v) systems;
        packages' = mapAttrs' (n: v: nameValuePair "package-${n}" v) packages;
      in
        homes' // systems' // packages' // {
          inherit shell;
        };
      ciDrv = pkgs.linkFarm "ci" ci;
    }));
}
