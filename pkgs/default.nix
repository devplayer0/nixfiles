{ lib, pkgs }:
let
  inherit (pkgs) callPackage;
in
{
  # yeah turns out this is in nixpkgs now... we'll leave it as a sample i guess lol
  monocraft' = callPackage ./monocraft.nix { };
}