{ lib }:
let
  inherit (builtins) length match replaceStrings elemAt mapAttrs head split filter;
  inherit (lib)
    genAttrs mapAttrs' mapAttrsToList filterAttrsRecursive nameValuePair types
    mkOption mkOverride mkForce mkIf mergeEqualOption optional hasPrefix
    showWarnings concatStringsSep flatten unique;
  inherit (lib.flake) defaultSystems;
in
rec {
  # Yoinked from nixpkgs/nixos/modules/services/networking/nat.nix
  isIPv6 = ip: length (lib.splitString ":" ip) > 2;
  parseIPPort = ipp:
    let
      v6 = isIPv6 ipp;
      matchIP = if v6 then "[[]([0-9a-fA-F:]+)[]]" else "([0-9.]+)";
      m = match "${matchIP}:(.+)" ipp;
      checked = v: if m == null then throw "bad ip:ports `${ipp}'" else v;
    in
    {
      inherit v6;
      ip = checked (elemAt m 0);
      ports = checked (elemAt m 1);
    };
  naiveIPv4Gateway = ip: "${head (elemAt (split ''([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+'' ip) 1)}.1";
  attrsToNVList = mapAttrsToList nameValuePair;

  mkDefaultSystemsPkgs = path: args': genAttrs defaultSystems (system: import path ((args' system) // { inherit system; }));
  mkApp = program: { type = "app"; inherit program; };
  mkShellApp = pkgs: name: text: mkApp (pkgs.writeShellScript name text).outPath;
  mkShellApp' = pkgs: args:
    let
      app = pkgs.writeShellApplication args;
    in mkApp "${app}/bin/${app.meta.mainProgram}";
  flakePackageOverlay' = flake: pkg: system: (final: prev:
    let
      pkg' = if pkg != null then flake.packages.${system}.${pkg} else flake.defaultPackage.${system};
      name = if pkg != null then pkg else pkg'.name;
    in
    {
      ${name} = pkg';
    });
  flakePackageOverlay = flake: flakePackageOverlay' flake null;

  inlineModule' = path: module: {
    _file = path;
    imports = [ module ];
  };
  inlineModule = path: inlineModule' path (import path);

  # Merge together modules which are defined as functions with others that aren't
  naiveModule = with types; (coercedTo (attrsOf anything) (conf: { ... }: conf) (functionTo (attrsOf anything)));

  mkOpt = type: default: mkOption { inherit type default; };
  mkOpt' = type: default: description: mkOption { inherit type default description; };
  mkBoolOpt = default: mkOption {
    inherit default;
    type = types.bool;
    example = true;
  };
  mkBoolOpt' = default: description: mkOption {
    inherit default description;
    type = types.bool;
    example = true;
  };
  nullOrOpt' = type: description: mkOpt' (types.nullOr type) null description;
  dummyOption = mkOption { };

  # Slightly higher precedence than mkDefault
  mkDefault' = mkOverride 900;
  mkVMOverride' = mkOverride 9;

  # This is shocking...
  duplicates = l:
    flatten
      (map
        (e:
          optional
            ((length (filter (e2: e2 == e) l)) > 1)
            e)
        (unique l));

  applyAssertions = config: res:
  let
    failedAssertions = map (x: x.message) (filter (x: !x.assertion) config.assertions);
  in
  if failedAssertions != []
    then throw "\nFailed assertions:\n${concatStringsSep "\n" (map (x: "- ${x}") failedAssertions)}"
    else showWarnings config.warnings res;

  homeStateVersion = hmBranch: {
    # The flake passes a default setting, but we don't care about that
    # Currently don't need any logic here, but we might need to use a newer version later
    #home.stateVersion = mkForce (if (hmBranch == "stable" || hmBranch == "mine-stable") then "22.05" else "22.11");
    home.stateVersion = mkForce "22.05";
  };

  commonOpts = with types; {
    moduleType = mkOptionType {
      name = "Inline flake-exportable module";
      merge = loc: defs: inlineModule (mergeEqualOption loc defs);
    };

    system = mkOpt' (enum defaultSystems) null "Nix-style system string.";
    nixpkgs = mkOpt' (enum [ "unstable" "stable" "mine" "mine-stable" ]) "unstable" "Branch of nixpkgs to use.";
    home-manager = mkOpt' (enum [ "unstable" "stable" "mine" "mine-stable" ]) "unstable" "Branch of home-manager to use.";
  };

  networkdAssignment = iface: a: {
    matchConfig.Name = iface;
    address =
      [ "${a.ipv4.address}/${toString a.ipv4.mask}" ] ++
      (optional (a.ipv6.iid == null) "${a.ipv6.address}/${toString a.ipv6.mask}");
    gateway =
      (optional (a.ipv4.gateway != null) a.ipv4.gateway) ++
      (optional (a.ipv6.gateway != null) a.ipv6.gateway);
    networkConfig = {
      IPv6AcceptRA = a.ipv6.gateway == null || a.ipv6.iid != null;
      # NOTE: LLDP emission / reception is ignored on bridge interfaces
      LLDP = true;
      EmitLLDP = "customer-bridge";
    };
    ipv6AcceptRAConfig = {
      Token = mkIf (a.ipv6.iid != null) "static:${a.ipv6.iid}";
      UseDNS = true;
      UseDomains = true;
    };
  };

  deploy-rs =
  with types;
  let
    globalOpts = {
      sshUser = nullOrOpt' str "Username deploy-rs will deploy with.";
      user = nullOrOpt' str "Username deploy-rs will deploy with.";
      sudo = nullOrOpt' str "Command to elevate privileges with (used if the deployment user != profile user).";
      sshOpts = mkOpt' (listOf str) [ ]
        "Options deploy-rs will pass to ssh. Note: overriding at a lower level _merges_ options.";
      fastConnection = nullOrOpt' bool "Whether to copy the whole closure instead of using substitution.";
      autoRollback = nullOrOpt' bool "Whether to roll back the profile if activation fails.";
      magicRollback = nullOrOpt' bool "Whether to roll back the profile if connectivity to the deployer is lost.";
      confirmTimeout = nullOrOpt' ints.u16 "Timeout for confirming activation succeeded.";
      tempPath = nullOrOpt' str "Path that deploy-rs will use for temporary files.";
    };

    profileOpts = {
      path = mkOpt' package "" "Derivation to build (should include activation script).";
      profilePath = nullOrOpt' str "Path to profile location";
    } // globalOpts;
    profileType = submodule { options = profileOpts; };

    nodeOpts = {
      hostname = mkOpt' str "" "Hostname deploy-rs will connect to.";
      profilesOrder = nullOrOpt' (listOf str)
        "Order to deploy profiles in (remainder will be deployed in arbitrary order).";
      profiles = mkOpt' (attrsOf profileType) { } "Profiles to deploy.";
    } // globalOpts;
    nodeType = submodule { options = nodeOpts; };

    deployOpts = {
      nodes = mkOption {
        type = attrsOf nodeType;
        default = { };
        internal = true;
        description = "deploy-rs node configurations.";
      };
    } // globalOpts;
    deployType = submodule { options = deployOpts; };
  in
  {
    inherit globalOpts;
    node = mkOpt' nodeType { } "deploy-rs node configuration.";
    deploy = mkOpt' deployType { } "deploy-rs configuration.";

    filterOpts = filterAttrsRecursive (_: v: v != null);
  };

  pubDomain = "nul.ie";
  colony = rec {
    domain = "fra1.int.${pubDomain}";
    start = {
      all = {
        v4 = "10.100.";
        v6 = "2a0e:97c0:4d0:ccc";
      };
      base = {
        v4 = "${start.all.v4}0.";
        v6 = "${start.all.v6}0::";
      };
      vms = {
        v4 = "${start.all.v4}1.";
        v6 = "${start.all.v6}1::";
      };
      ctrs = {
        v4 = "${start.all.v4}2.";
        v6 = "${start.all.v6}2::";
      };
    };
    prefixes = {
      all = {
        v4 = "${start.base.v4}0/16";
        v6 = "${start.base.v6}/60";
      };
      base.v6 = "${start.base.v6}/64";
      vms = {
        v4 = "${start.vms.v4}0/24";
        v6 = "${start.vms.v6}/64";
      };
      ctrs = {
        v4 = "${start.ctrs.v4}0/24";
        v6 = "${start.ctrs.v6}/64";
      };
    };
  };
  sshKeyFiles = {
    me = ../.keys/me.pub;
    deploy = ../.keys/deploy.pub;
  };
}
