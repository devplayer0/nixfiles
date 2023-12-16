{ lib }:
let
  inherit (builtins) length match elemAt filter replaceStrings;
  inherit (lib)
    genAttrs mapAttrsToList filterAttrsRecursive nameValuePair types
    mkOption mkOverride mkForce mkIf mergeEqualOption optional
    showWarnings concatStringsSep flatten unique optionalAttrs;
  inherit (lib.flake) defaultSystems;
in
rec {
  pow =
    let
      pow' = base: exponent: value:
        # FIXME: It will silently overflow on values > 2**62 :(
        # The value will become negative or zero in this case
        if exponent == 0
        then 1
        else if exponent <= 1
        then value
        else (pow' base (exponent - 1) (value * base));
    in base: exponent: pow' base exponent base;

  attrsToNVList = mapAttrsToList nameValuePair;

  inherit (import ./net.nix { inherit lib; }) net;
  dns = import ./dns.nix { inherit lib; };
  c = import ./constants.nix { inherit lib; };

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

  netBroadcast = net': net.cidr.host ((pow 2 (net.cidr.size net')) - 1) net';

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

  homeStateVersion' = hmBranch: (if (hmBranch == "stable" || hmBranch == "mine-stable") then "22.11" else "23.05");
  homeStateVersion = hmBranch: {
    # The flake passes a default setting, but we don't care about that
    home.stateVersion = mkForce (homeStateVersion' hmBranch);
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

  nft = rec {
    ipEscape = replaceStrings ["." ":"] ["-" "-"];
    natFilterChain = ip: "filter-fwd-${ipEscape ip}";
    dnatChain = ip: "fwd-${ipEscape ip}";
  };

  mkVLAN = name: vid: {
    "25-${name}" = {
      netdevConfig = {
        Name = name;
        Kind = "vlan";
      };
      vlanConfig.Id = vid;
    };
  };
  networkdAssignment = iface: a: {
    matchConfig.Name = iface;
    address =
      [ "${a.ipv4.address}/${toString a.ipv4.mask}" ] ++
      (optional (a.ipv6.address != null && a.ipv6.iid == null) "${a.ipv6.address}/${toString a.ipv6.mask}");
    gateway =
      (optional (a.ipv4.gateway != null) a.ipv4.gateway) ++
      (optional (a.ipv6.gateway != null) a.ipv6.gateway);
    networkConfig = {
      IPv6AcceptRA = a.ipv6.gateway == null || a.ipv6.iid != null;
      # NOTE: LLDP emission / reception is ignored on bridge interfaces
      LLDP = true;
      EmitLLDP = "customer-bridge";
    };
    linkConfig = optionalAttrs (a.mtu != null) {
      MTUBytes = toString a.mtu;
    };
    ipv6AcceptRAConfig = {
      Token = mkIf (a.ipv6.iid != null) "static:${a.ipv6.iid}";
      UseDNS = true;
      UseDomains = true;
    };
  };
  dockerNetAssignment =
    assignments: name: with assignments."${name}".internal; "ip=${ipv4.address},ip=${ipv6.address}";

  systemdAwaitPostgres = pkg: host: {
    after = [ "systemd-networkd-wait-online.service" ];
    preStart = ''
      until ${pkg}/bin/pg_isready -h ${host}; do
        sleep 0.5
      done
    '';
  };

  vm = rec {
    lvmDisk' = name: lv: {
      inherit name;
      backend = {
        driver = "host_device";
        filename = "/dev/main/${lv}";
        # It appears this needs to be set on the backend _and_ the format
        discard = "unmap";
      };
      format = {
        driver = "raw";
        discard = "unmap";
      };
      frontend = "virtio-blk";
    };
    lvmDisk = lv: lvmDisk' lv lv;
    disk = vm: lv: lvmDisk' lv "vm-${vm}-${lv}";
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
}
