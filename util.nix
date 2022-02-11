{ lib }:
  let
    inherit (lib) genAttrs mapAttrs' types mkOption mkOverride;
    inherit (lib.flake) defaultSystems;
  in {
    addPrefix = prefix: mapAttrs' (n: v: { name = "${prefix}${n}"; value = v; });
    mkPkgs = path: args: genAttrs defaultSystems (system: import path (args // { inherit system; }));

    mkOpt = type: default: mkOption { inherit type default; };
    mkBoolOpt = default: mkOption {
      inherit default;
      type = types.bool;
      example = true;
    };
    mkVMOverride' = mkOverride 9;
    dummyOption = mkOption {};
  }
