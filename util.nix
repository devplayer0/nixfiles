{ lib }:
let
  inherit (builtins) replaceStrings elemAt;
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

  mkPkgs = path: args: genAttrs defaultSystems (system: import path (args // { inherit system; }));
  mkApp = program: { type = "app"; inherit program; };

  mkOpt = type: default: mkOption { inherit type default; };
  mkBoolOpt = default: mkOption {
    inherit default;
    type = types.bool;
    example = true;
  };
  mkVMOverride' = mkOverride 9;
  dummyOption = mkOption { };
}
