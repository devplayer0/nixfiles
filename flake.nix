{
  description = "System configs";

  # Offer our Harmonia cache when building the flake itself, so `nix develop` / `nix build` don't
  # rebuild from source. Nix reads `nixConfig` before the flake evaluates and rejects any computed
  # value (imports/thunks), so these must stay literal — keep them in sync with `lib.my.c.nix.cache`.
  # Consumers must trust these (accept-flake-config / a trusted user) for them to take effect.
  nixConfig = {
    extra-substituters = [
      "https://nix-cache.nul.ie"
    ];
    extra-trusted-public-keys = [
      "nix-cache.nul.ie-1:BzH5yMfF4HbzY1C977XzOxoPhEc9Zbu39ftPkUbH+m4="
    ];
  };

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    # libnet.url = "github:reo101/nix-lib-net";
    libnetRepo = {
      url = "github:oddlama/nixos-extra-modules";
      flake = false;
    };
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "nixpkgs/nixos-26.05";
    nixpkgs-mine.url = "github:devplayer0/nixpkgs/devplayer0";
    nixpkgs-mine-stable.url = "github:devplayer0/nixpkgs/devplayer0-stable";

    home-manager-unstable.url = "home-manager";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";
    home-manager-stable.url = "home-manager/release-26.05";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    # Determinate Nix, used as the common Nix implementation across systems, homes, the devshell and
    # CI (see lib.my.c.nix). We build it ourselves against our pinned nixpkgs (FlakeHub's cache needs
    # auth), so it flows through our own Harmonia cache like everything else.
    determinate-nix.url = "https://flakehub.com/f/DeterminateSystems/nix-src/*";
    determinate-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # Stuff used by the flake for build / deployment
    # ragenix.url = "github:yaxitech/ragenix";
    ragenix.url = "github:devplayer0/ragenix/add-rekey-one-flag";
    ragenix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # Stuff used by systems
    impermanence.url = "github:nix-community/impermanence";
    impermanence.inputs.home-manager.follows = "home-manager-unstable";
    boardie.url = "github:devplayer0/boardie";
    boardie.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nixGL.url = "github:nix-community/nixGL";
    nixGL.inputs.nixpkgs.follows = "nixpkgs-unstable";
    harmonia.url = "github:nix-community/harmonia";
    # harmonia.url = "github:devplayer0/harmonia/cache-config-daemon-store";
    harmonia.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # Firmware building for the OpenWrt boxes, which aren't managed by this flake otherwise.
    # `openwrt-feeds` pins the package feeds; without it, evaluation would reach the OpenWrt
    # download server over import-from-derivation and break on hashes that upstream rotates daily.
    openwrt-imagebuilder.url = "github:astro/nix-openwrt-imagebuilder";
    openwrt-imagebuilder.inputs.nixpkgs.follows = "nixpkgs-unstable";
    openwrt-feeds.url = "github:devplayer0/openwrt-feeds";
    openwrt-feeds.inputs.nixpkgs.follows = "nixpkgs-unstable";
    openwrt-feeds.inputs.openwrt-imagebuilder.follows = "openwrt-imagebuilder";

    # Packages not in nixpkgs
    sharry.url = "github:eikek/sharry";
    sharry.inputs.nixpkgs.follows = "nixpkgs-unstable";
    borgthin.url = "github:devplayer0/borg";
    # TODO: Update borgthin so this works
    # borgthin.inputs.nixpkgs.follows = "nixpkgs-mine";
    copyparty.url = "github:9001/copyparty";
    copyparty.inputs.nixpkgs.follows = "nixpkgs-unstable";
    hass-west-wood.url = "github:devplayer0/hass-west-wood";
    hass-west-wood.inputs.nixpkgs.follows = "nixpkgs-unstable";
    # Disabled: `pi-coding-agent-bun` breaks `nix flake check` in CI. Its bun2nix `fetchBunDeps`
    # calls `builtins.filterSource` on subpaths of the pi.nix flake source (coding-agent/bun.nix),
    # which requires that source derivation to be realised in the local store. On a fresh CI runner
    # it isn't, so eval aborts with `path '…-source.drv' is not valid`. Works locally only because
    # the source is already realised there. Re-enable (and revisit upstream) if we start using pi.
    # pi-agent.url = "github:lukasl-dev/pi.nix";
    # pi-agent.inputs.nixpkgs.follows = "nixpkgs-unstable";
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
        my = import ./lib { inherit inputs; lib = final; };
        flake = flake-utils.lib;
      };
      pkgsLibOverlay = final: prev: { lib = prev.lib.extend libOverlay; };
      myPkgsOverlay = final: prev: import ./pkgs { lib = final.lib; pkgs = prev; };
      # Exposes Determinate Nix under a stable attr name so systems, homes and the devshell all
      # resolve the exact same package (referenced as `pkgs'.mine.determinate-nix` in configs).
      # `nix-util`'s `readLinkAt.works` unit test creates PATH_MAX-length symlinks, which our CI
      # runner's XFS-backed build filesystem rejects (XFS hard-caps symlink targets at 1024 bytes).
      # Skip just that test via gtest's GTEST_FILTER so the rest of the suite still gates the build.
      determinateOverlay = final: prev: {
        determinate-nix =
          (inputs.determinate-nix.packages.${prev.stdenv.hostPlatform.system}.default).overrideAttrs (o: {
            checkInputs = map
              (drv:
                if (drv.name or "") == "nix-util-tests-run"
                then drv.overrideAttrs (_: { GTEST_FILTER = "-readLinkAt.*"; })
                else drv)
              o.checkInputs;
          });
      };

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
            determinateOverlay
            inputs.devshell.overlays.default
            inputs.ragenix.overlays.default
            inputs.deploy-rs.overlays.default
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
            determinateOverlay
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
        nixos/boxes/colony/portcullis
        nixos/boxes/tower
        nixos/boxes/home/stream.nix
        nixos/boxes/home/palace
        nixos/boxes/home/castle
        nixos/boxes/britway
        nixos/boxes/britnet.nix
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
      inherit inputs lib nixfiles;

      overlays.default = myPkgsOverlay;

      nixosModules = nixfiles.config.nixos.modules;
      homeModules = nixfiles.config.home-manager.modules;

      # Containers and the installer override `rendered` with a bare `extendModules` config
      # (`my.asContainer` / `my.asISO`) that lacks the `pkgs`/`lib` attrs `eval-config` exposes on a
      # normal system. Determinate Nix's flake schemas read `machine.pkgs.stdenv.system` for every
      # `nixosConfigurations` entry, so re-attach them from the full system eval (`configuration`).
      nixosConfigurations = mapAttrs
        (_: s: s.rendered // { inherit (s.configuration) pkgs lib; })
        nixfiles.config.nixos.systems;
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

      packages = flattenTree (
        (import ./pkgs { inherit lib pkgs; }) //
        (import ./openwrt { inherit pkgs inputs; }));

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
