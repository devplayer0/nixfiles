{
  description = "System configs";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    # Used by most systems
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    # For extra-stable systems
    nixpkgs-stable.url = "nixpkgs/nixos-21.11";

    # Stuff used by the flake for build / deployment
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # Stuff used by systems
    nix.url = "nix/latest-release";
    #impermanence.url = "github:nix-community/impermanence";
    impermanence.url = "github:devplayer0/impermanence/qemu-vm-dirs";
  };

  outputs =
    inputs@{
      self,

      flake-utils,

      nixpkgs-unstable, nixpkgs-stable,

      ...
    }:
    let
      inherit (builtins) mapAttrs;
      inherit (lib) genAttrs mapAttrs';
      inherit (lib.flake) defaultSystems eachDefaultSystem;
      inherit (lib.my) addPrefix mkApp mkShellApp;

      extendLib = lib: lib.extend (final: prev: {
        my = import ./util.nix { lib = final; };
        flake = flake-utils.lib;
      });
      libOverlay = final: prev: { lib = extendLib prev.lib; };

      pkgsFlakes = mapAttrs (_: pkgs: pkgs // { lib = extendLib pkgs.lib; }) {
        unstable = nixpkgs-unstable;
        stable = nixpkgs-stable;
      };

      lib = pkgsFlakes.unstable.lib;

      pkgs' = mapAttrs
        (_: path: lib.my.mkDefaultSystemsPkgs path {
          overlays = [
            libOverlay
            inputs.agenix.overlay
            inputs.deploy-rs.overlay
            inputs.nix.overlay
          ];
        })
        pkgsFlakes;
    in
    # Platform independent stuff
    {
      lib = lib.my;

      nixosModules = mapAttrs
        (_: path:
          let path' = ./. + "/modules/${path}"; in
          {
            _file = path';
            imports = [ (import path') ];
          })
        {
          common = "common.nix";
          build = "build.nix";
          dynamic-motd = "dynamic-motd.nix";
          tmproot = "tmproot.nix";
          firewall = "firewall.nix";
          server = "server.nix";
        };

      nixosConfigurations = import ./systems.nix { inherit lib pkgsFlakes inputs; modules = self.nixosModules; };
      systems = mapAttrs (_: system: system.config.system.build.toplevel) self.nixosConfigurations;
      vms = mapAttrs (_: system: system.config.my.build.devVM) self.nixosConfigurations;
    } //
    (eachDefaultSystem (system:
    let
      pkgs = pkgs'.unstable.${system};
      lib = pkgs.lib;
    in
    # Stuff for each platform
    {
      apps = {
        fmt = mkShellApp pkgs "fmt" ''exec "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt" "$@" .'';
      };

      devShell = pkgs.mkShell {
        packages = with pkgs; [
          nix
          agenix
          deploy-rs.deploy-rs
          nixpkgs-fmt
        ];
      };
    }));
}
