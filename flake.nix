{
  description = "System configs";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nixpkgs-master.url = "nixpkgs";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "nixpkgs/nixos-21.11";
    nixpkgs-mine.url = "github:devplayer0/nixpkgs";

    home-manager-unstable.url = "home-manager";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";
    home-manager-stable.url = "home-manager/release-21.11";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    # Stuff used by the flake for build / deployment
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # Stuff used by systems
    #impermanence.url = "github:nix-community/impermanence";
    impermanence.url = "github:devplayer0/impermanence/qemu-vm-dirs";
  };

  outputs =
    inputs@{
      self,

      flake-utils,

      nixpkgs-master, nixpkgs-unstable, nixpkgs-stable, nixpkgs-mine,
      home-manager-unstable, home-manager-stable,

      ...
    }:
    let
      inherit (builtins) mapAttrs attrValues;
      inherit (lib) recurseIntoAttrs filterAttrs;
      inherit (lib.flake) flattenTree eachDefaultSystem;
      inherit (lib.my) inlineModules mkDefaultSystemsPkgs flakePackageOverlay;

      # Extend a lib with extras that _must not_ internally reference private nixpkgs. flake-utils doesn't, but many
      # other flakes (e.g. home-manager) probably do internally.
      libOverlay = final: prev: {
        my = import ./lib.nix { lib = final; };
        flake = flake-utils.lib;
      };
      pkgsLibOverlay = final: prev: { lib = prev.lib.extend libOverlay; };

      # Override the flake-level lib since we're going to use it for non-config specific stuff
      pkgsFlakes = mapAttrs (_: pkgsFlake: pkgsFlake // { lib = pkgsFlake.lib.extend libOverlay; }) {
        master = nixpkgs-master;
        unstable = nixpkgs-unstable;
        stable = nixpkgs-stable;
        mine = nixpkgs-mine;
      };
      hmFlakes = {
        unstable = home-manager-unstable;
        stable = home-manager-stable;
      };

      # Should only be used for platform-independent flake stuff! This should never leak into a NixOS or home-manager
      # config - they'll get their own.
      lib = pkgsFlakes.unstable.lib;

      # pkgs for dev shell etc
      pkgs' = mapAttrs
        (_: path: mkDefaultSystemsPkgs path (system: {
          overlays = [
            pkgsLibOverlay
            inputs.devshell.overlay
            inputs.agenix.overlay
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
          ];
        }))
        pkgsFlakes;

      modules = mapAttrs (_: f: ./. + "/nixos/modules/${f}") {
        common = "common.nix";
        user = "user.nix";
        build = "build.nix";
        dynamic-motd = "dynamic-motd.nix";
        tmproot = "tmproot.nix";
        firewall = "firewall.nix";
        server = "server.nix";
        deploy-rs = "deploy-rs.nix";
      };
      homeModules = mapAttrs (_: f: ./. + "/home-manager/modules/${f}") {
        common = "common.nix";
        gui = "gui.nix";
      };
    in
    # Platform independent stuff
    {
      lib = lib.my;
      nixpkgs = pkgs';

      nixosModules = inlineModules modules;
      homeModules = inlineModules homeModules;

      # TODO: Cleanup and possibly even turn into modules?
      nixosConfigurations = import ./nixos {
        inherit lib pkgsFlakes hmFlakes inputs;
        pkgs' = configPkgs';
        modules = attrValues modules;
        homeModules = attrValues homeModules;
      };
      systems = mapAttrs (_: system: system.config.system.build.toplevel) self.nixosConfigurations;
      vms = mapAttrs (_: system: system.config.my.buildAs.devVM) self.nixosConfigurations;
      isos = mapAttrs (_: system: system.config.my.buildAs.iso) self.nixosConfigurations;

      homeConfigurations = import ./home-manager {
        inherit lib hmFlakes inputs;
        pkgs' = configPkgs';
        modules = attrValues homeModules;
      };
      homes = mapAttrs (_: home: home.activationPackage) self.homeConfigurations;

      deploy = {
        nodes = filterAttrs (_: n: n != null)
          (mapAttrs (_: system: system.config.my.deploy.rendered) self.nixosConfigurations);

        autoRollback = true;
        magicRollback = true;
      };
    } //
    (eachDefaultSystem (system:
    let
      pkgs = pkgs'.unstable.${system};
      lib = pkgs.lib;
    in
    # Stuff for each platform
    {
      checks = flattenTree {
        homeConfigurations = recurseIntoAttrs self.homes;
        deploy = recurseIntoAttrs (pkgs.deploy-rs.lib.deployChecks self.deploy);
      };

      devShell = pkgs.devshell.mkShell ./devshell;
    }));
}
