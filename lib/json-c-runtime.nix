{ lib, pkgs, pkgsFlake }:

# TODO: Drop this when updating the fork pin to a revision with the json-c fix.
# Patch the runtime library separately so existing consumers can be reused.
lib.optional ((pkgsFlake.rev or null) == "320600d55ff67365e933b98b339acdeac238eb26") {
  oldDependency = pkgs.json_c;
  newDependency = pkgs.json_c.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ (pkgs.fetchpatch {
      url = "https://github.com/json-c/json-c/commit/f291fa81c6f21d925ea771a8cca597f5886309cc.patch";
      hash = "sha256-ZffSw1pfEfOH2ylRpJShdx7sTQR2nmPM/JIj/26UrDM=";
    }) ];
  });
}
