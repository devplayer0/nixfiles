{ lib, pkgs, ... }:
let
  inherit (lib.my) attrsToNVList;
in
{
  imports = [ ./commands.nix ./install.nix ];

  env = attrsToNVList {
    # starship will show this
    name = "devshell";

    NIX_USER_CONF_FILES = toString (pkgs.writeText "nix.conf"
      ''
        experimental-features = nix-command flakes ca-derivations
      '');
  };

  packages = with pkgs; [
    coreutils
    nixVersions.stable
    agenix
    deploy-rs.deploy-rs
    home-manager
  ];
}
