{ lib }:
let
  inherit (builtins) replaceStrings elemAt mapAttrs;
  inherit (lib) genAttrs mapAttrs' types mkOption mkOverride;
  inherit (lib.flake) defaultSystems;
in
rec {
  addPrefix = prefix: mapAttrs' (n: v: { name = "${prefix}${n}"; value = v; });
  # Yoinked from nixpkgs/nixos/modules/services/networking/nat.nix
  isIPv6 = ip: builtins.length (lib.splitString ":" ip) > 2;
  parseIPPort = ipp:
    let
      v6 = isIPv6 ipp;
      matchIP = if v6 then "[[]([0-9a-fA-F:]+)[]]" else "([0-9.]+)";
      m = builtins.match "${matchIP}:([0-9-]+)" ipp;
      checked = v: if m == null then throw "bad ip:ports `${ipp}'" else v;
    in
    {
      inherit v6;
      ip = checked (elemAt m 0);
      ports = checked (replaceStrings ["-"] [":"] (elemAt m 1));
    };

  mkDefaultSystemsPkgs = path: args': genAttrs defaultSystems (system: import path ((args' system) // { inherit system; }));
  mkApp = program: { type = "app"; inherit program; };
  mkShellApp = pkgs: name: text: mkApp (pkgs.writeShellScript name text).outPath;
  inlineModules = modules: mapAttrs
    (_: path:
      {
        _file = path;
        imports = [ (import path) ];
      })
    modules;
  flakePackageOverlay' = flake: pkg: system: (final: prev:
    let
      pkg' = if pkg != null then flake.packages.${system}.${pkg} else flake.defaultPackage.${system};
      name = if pkg != null then pkg else pkg'.name;
    in
    {
      ${name} = pkg';
    });
  flakePackageOverlay = flake: flakePackageOverlay' flake null;

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
  dummyOption = mkOption { };

  mkVMOverride' = mkOverride 9;
}
