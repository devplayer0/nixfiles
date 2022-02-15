{
  description = "System configs";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs-unstable";
    # Used by most systems
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    # For extra-stable systems
    nixpkgs-stable.url = "nixpkgs/nixos-21.11";

    # Stuff used by the flake for build / deployment
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs-unstable";
    home-manager.url = "home-manager";
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
      inherit (builtins) mapAttrs attrValues;
      inherit (lib.flake) eachDefaultSystem;
      inherit (lib.my) attrsToList mkApp mkShellApp mkShellApp' inlineModules mkDefaultSystemsPkgs flakePackageOverlay;

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
        (_: path: mkDefaultSystemsPkgs path (system: {
          overlays = [
            libOverlay
            inputs.devshell.overlay
            inputs.agenix.overlay
            inputs.deploy-rs.overlay
            inputs.nix.overlay
            (flakePackageOverlay inputs.home-manager system)
          ];
        }))
        pkgsFlakes;

      # Easiest to build the basic pkgs here (with our lib overlay too)
      homePkgs' = mapAttrs
        (_: path: mkDefaultSystemsPkgs path (_: {
          overlays = [
            libOverlay
          ];
        }))
        pkgsFlakes;

      modules = mapAttrs (_: f: ./. + "/modules/${f}") {
        common = "common.nix";
        build = "build.nix";
        dynamic-motd = "dynamic-motd.nix";
        tmproot = "tmproot.nix";
        firewall = "firewall.nix";
        server = "server.nix";
      };
      homeModules = mapAttrs (_: f: ./. + "/home-modules/${f}") {
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

      nixosConfigurations = import ./systems.nix {
        inherit lib pkgsFlakes inputs;
        modules = attrValues modules;
        homeModules = attrValues homeModules;
      };
      systems = mapAttrs (_: system: system.config.system.build.toplevel) self.nixosConfigurations;
      vms = mapAttrs (_: system: system.config.my.build.devVM) self.nixosConfigurations;

      homeConfigurations = import ./homes.nix {
        inherit lib inputs;
        pkgs' = homePkgs';
        modules = attrValues homeModules;
      };
      homes = mapAttrs(_: home: home.activationPackage) self.homeConfigurations;
    } //
    (eachDefaultSystem (system:
    let
      homeFlake = "$HOME/.config/nixpkgs/flake.nix";

      pkgs = pkgs'.unstable.${system};
      lib = pkgs.lib;
    in
    # Stuff for each platform
    {
      devShell = pkgs.devshell.mkShell {
        env = attrsToList {
          # starship will show this
          name = "devshell";

          NIX_USER_CONF_FILES = toString (pkgs.writeText "nix.conf"
            ''
              experimental-features = nix-command flakes ca-derivations
            '');
        };

        packages = with pkgs; [
          coreutils
          nix
          agenix
          deploy-rs.deploy-rs
          home-manager
        ];

        commands = [
          {
            name = "repl";
            category = "utilities";
            help = "Open a `nix repl` with this flake";
            command = ''nix repl ${pkgs.writeText "repl.nix" "builtins.getFlake \"${./.}\""}'';
          }
          {
            name = "home-link";
            category = "utilities";
            help = "Install link to flake.nix for home-manager to use";
            command =
              ''
                [ -e "${homeFlake}" ] && echo "${homeFlake} already exists" && exit 1

                mkdir -p "$(dirname "${homeFlake}")"
                ln -s "$(pwd)/flake.nix" "${homeFlake}"
                echo "Installed link to $(pwd)/flake.nix at ${homeFlake}"
              '';
          }
          {
            name = "home-unlink";
            category = "utilities";
            help = "Remove home-manager flake.nix link";
            command = "rm -f ${homeFlake}";
          }

          {
            name = "fmt";
            category = "tasks";
            help = pkgs.nixpkgs-fmt.meta.description;
            command = ''exec "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt" "$@"'';
          }
          {
            name = "home-switch";
            category = "tasks";
            help = "Run `home-manager switch`";
            command = ''home-manager switch --flake . "$@"'';
          }
        ];
      };
    }));
}
