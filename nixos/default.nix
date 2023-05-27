{ lib, pkgsFlakes, hmFlakes, inputs, pkgs', config, ... }:
let
  inherit (builtins) attrValues mapAttrs;
  inherit (lib)
    substring flatten optional optionals mkIf mkDefault mkForce mkOption mkOptionType foldAttrs mapAttrsToList;
  inherit (lib.my)
    homeStateVersion mkOpt' mkBoolOpt' mkDefault' commonOpts inlineModule' applyAssertions duplicates net;

  cfg = config.nixos;

  allAssignments = (mapAttrs (_: c: c.assignments) cfg.systems) // (foldAttrs (c: all: all // c) { } (mapAttrsToList (_: c: c.extraAssignments) cfg.systems));

  mkSystem =
    {
      name,
      config',
      defs,
    }:
    let
      # The flake contains `nixosSystem`, so we do need it
      pkgsFlake = pkgsFlakes.${config'.nixpkgs};

      pkgs = pkgs'.${config'.nixpkgs}.${config'.system};
      allPkgs = mapAttrs (_: p: p.${config'.system}) pkgs';

      modules' = [ hmFlakes.${config'.home-manager}.nixosModule ] ++ (attrValues cfg.modules);
    in
    pkgsFlake.lib.nixosSystem {
      # Gotta override lib here unforunately, eval-config.nix likes to import its own (unextended) lib. We explicitly
      # don't pass pkgs so that it'll be imported with modularly applied config and overlays.
      lib = pkgs.lib;

      # Put the inputs in specialArgs to avoid infinite recursion when modules try to do imports
      specialArgs = { inherit inputs pkgsFlakes pkgsFlake allAssignments; inherit (cfg) systems; };

      # `baseModules` informs the manual which modules to document
      baseModules =
        (import "${pkgsFlake}/nixos/modules/module-list.nix") ++ (optionals config'.docCustom modules');
      modules = (optionals (!config'.docCustom) modules') ++ [
        (sysModArgs: {
          warnings = flatten [
            (optional (sysModArgs.config.home-manager.useGlobalPkgs && (config'.nixpkgs != config'.home-manager))
            ''
              Using global nixpkgs ${config'.nixpkgs} with home-manager ${config'.home-manager} may cause problems.
            '')
          ];

          _module.args = {
            inherit (cfg) secretsPath vpns;
            inherit (config') assignments;
            pkgs' = allPkgs;
          };

          system.name = name;
          networking = {
            domain = let d = config'.assignments.internal.domain or null; in mkIf (d != null) (mkDefault' d);
            hostName = mkDefault (config'.assignments.internal.name or name);
          };
          nixpkgs = {
            inherit (config') system;
            # Make sure any previously set overlays (e.g. lib which will be inherited by home-manager down the
            # line) are passed on when nixpkgs is imported. We don't inherit config anymore because apparently it
            # doesn't seem to merge properly... (https://github.com/NixOS/nixpkgs/blob/14a348fcc6c0d28804f640375f058d5491c2e1ee/nixos/modules/misc/nixpkgs.nix#L34)
            # TODO: Possible this behaviour will be fixed in future?
            inherit (pkgs) overlays;
          };

          # Unfortunately it seems there's no way to fully decouple home-manager's lib from NixOS's pkgs.lib. :(
          # https://github.com/nix-community/home-manager/blob/7c2ae0bdd20ddcaafe41ef669226a1df67f8aa06/nixos/default.nix#L22
          home-manager = {
            extraSpecialArgs = { inherit inputs; };
            # Optimise if system and home-manager nixpkgs are the same
            useGlobalPkgs = mkDefault (config'.nixpkgs == config'.hmNixpkgs);
            sharedModules = (attrValues config.home-manager.modules) ++ [
              {
                warnings = flatten [
                  (optional (!sysModArgs.config.home-manager.useGlobalPkgs && (config'.hmNixpkgs != config'.home-manager))
                  ''
                    Using per-user nixpkgs ${config'.hmNixpkgs} with home-manager ${config'.home-manager}
                    may cause issues.
                  '')
                ];

                # pkgsPath is used by home-manager's nixpkgs module to import nixpkgs (i.e. if !useGlobalPkgs)
                _module.args = {
                  pkgsPath = toString pkgsFlakes.${config'.hmNixpkgs};
                  pkgs' = allPkgs;
                };
              }
              (homeStateVersion config'.home-manager)
            ];
          };
        })
      ] ++ defs;
    };

  assignmentOpts = with lib.types; { name, config, ... }: {
    options = {
      name = mkOpt' str name "Name of assignment.";
      altNames = mkOpt' (listOf str) [ ] "Extra names to assign.";
      visible = mkBoolOpt' true "Whether or not this assignment should be visible.";
      domain = mkOpt' (nullOr str) null "Domain for this assignment.";
      ipv4 = {
        address = mkOpt' net.types.ipv4 null "IPv4 address.";
        mask = mkOpt' ints.u8 24 "Network mask.";
        gateway =
          mkOpt' (nullOr str) (net.cidr.host 1 "${config.ipv4.address}/${toString config.ipv4.mask}") "IPv4 gateway.";
        genPTR = mkBoolOpt' true "Whether to generate a PTR record.";
      };
      ipv6 = {
        address = mkOpt' (nullOr net.types.ipv6) null "IPv6 address.";
        mask = mkOpt' ints.u8 64 "Network mask.";
        iid = mkOpt' (nullOr str) null "SLAAC static address.";
        gateway = mkOpt' (nullOr str) null "IPv6 gateway.";
        genPTR = mkBoolOpt' true "Whether to generate a PTR record.";
      };
    };
  };

  l2PeerOpts = with lib.types; {
    options = {
      addr = mkOpt' str null "Address.";
    };
  };
  l2MeshOpts = with lib.types; { name, ... }: {
    options = {
      interface = mkOpt' str name "Name of VXLAN interface.";
      firewall = mkBoolOpt' true "Whether to generate firewall rules.";
      vni = mkOpt' ints.unsigned 1 "VXLAN VNI.";
      peers = mkOpt' (attrsOf (submodule l2PeerOpts)) { } "Peers.";
      security = {
        enable = mkBoolOpt' true "Whether to enable IPsec authentication.";
        encrypt = mkBoolOpt' false "Whether to enable IPsec encryption.";
      };
    };
  };

  systemOpts = with lib.types; { name, ... }@args:
  let
    config' = args.config;
  in
  {
    options = {
      inherit (commonOpts) system nixpkgs home-manager;
      hmNixpkgs = commonOpts.nixpkgs;
      # This causes a (very slow) docs rebuild on every change to a module's options it seems
      # TODO: Currently broken with infinite recursion...
      docCustom = mkBoolOpt' false "Whether to document nixfiles' custom NixOS modules.";

      assignments = mkOpt' (attrsOf (submoduleWith {
        modules = [ assignmentOpts { _module.args.name = mkForce name; } ];
      })) { } "Network assignments.";
      # TODO: Getting the default name for the extra assignment is currently fucked for the same reason as above
      extraAssignments = mkOpt' (attrsOf (attrsOf (submodule assignmentOpts))) { } "Extra network assignments.";

      configuration = mkOption {
        description = "NixOS configuration module.";
        # Based on the definition of containers.<name>.config
        type = mkOptionType {
          name = "Toplevel NixOS config";
          merge = _: defs: applyAssertions config (mkSystem {
            inherit name config';
            defs = map (d: inlineModule' d.file d.value) defs;
          });
        };
      };
    };

    config = {
      home-manager = mkDefault config'.nixpkgs;
      hmNixpkgs = mkDefault config'.nixpkgs;
    };
  };
in
{
  imports = [ modules/_list.nix ];

  options = with lib.types; {
    nixos = {
      secretsPath = mkOpt' path null "Path to encrypted secret files.";
      modules = mkOpt' (attrsOf commonOpts.moduleType) { } "NixOS modules to be exported by nixfiles.";
      systems = mkOpt' (attrsOf (submodule systemOpts)) { } "NixOS systems to be exported by nixfiles.";
      vpns = {
        l2 = mkOpt' (attrsOf (submodule l2MeshOpts)) { } "Layer 2 meshes.";
      };
    };
  };

  config = {
    assertions =
    let
      assignedIPs =
        flatten
          (map
            (as:
              map
                (a: [ a.ipv4.address ] ++ (optional (a.ipv6.address != null) a.ipv6.address) )
                (attrValues as))
            (attrValues allAssignments));
      dupIPs = duplicates assignedIPs;
    in
    [
      {
        assertion = dupIPs == [ ];
        message = "Duplicate assignments: ${toString dupIPs}";
      }
    ];
  };
}
