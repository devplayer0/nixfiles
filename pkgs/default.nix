{ lib, pkgs }:
let
  inherit (pkgs) callPackage;
in
{
  # yeah turns out this is in nixpkgs now... we'll leave it as a sample i guess lol
  monocraft' = callPackage ./monocraft.nix { };
  vfio-pci-bind = callPackage ./vfio-pci-bind.nix { };
  librespeed-go = callPackage ./librespeed-go.nix { };
  modrinth-app = callPackage ./modrinth-app { };
  glfw-minecraft = callPackage ./glfw-minecraft { };
  chocolate-doom2xx = callPackage ./chocolate-doom2xx.nix { };
}
