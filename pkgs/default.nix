{ lib, pkgs }:
let
  inherit (pkgs) callPackage;
in
{
  # yeah turns out this is in nixpkgs now... we'll leave it as a sample i guess lol
  monocraft' = callPackage ./monocraft.nix { };
  vfio-pci-bind = callPackage ./vfio-pci-bind.nix { };
  librespeed-go = callPackage ./librespeed-go.nix { };
  # modrinth-app = callPackage ./modrinth-app { };
  chocolate-doom2xx = callPackage ./chocolate-doom2xx { };
  windowtolayer = callPackage ./windowtolayer.nix { };
  swaylock-plugin = callPackage ./swaylock-plugin.nix { };
  firefox-memory-control = callPackage ./firefox-memory-control { };

  update-docs-assignments = pkgs.writeShellScriptBin "update-docs-assignments" ''
    exec ${pkgs.python3}/bin/python3 ${../ci/update-docs-assignments.py} "$@"
  '';

  update-docs-options = pkgs.writeShellScriptBin "update-docs-options" ''
    exec ${pkgs.python3}/bin/python3 ${../ci/update-docs-options.py} "$@"
  '';

  update-docs-dns =
    let
      python = pkgs.python3.withPackages (ps: [ ps.dnspython ]);
    in
    pkgs.writeShellScriptBin "update-docs-dns" ''
      exec ${python}/bin/python3 ${../ci/update-docs-dns.py} "$@"
    '';
}
