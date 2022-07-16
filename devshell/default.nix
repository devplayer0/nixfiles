{ lib, pkgs, ... }:
let
  inherit (lib.my) attrsToNVList;
in
{
  imports = [ ./commands.nix ./install.nix ./vm-tasks.nix ];

  env = attrsToNVList {
    # starship will show this
    name = "devshell";

    NIX_USER_CONF_FILES = toString (pkgs.writeText "nix.conf"
      ''
        experimental-features = nix-command flakes ca-derivations
        substituters = https://nix-cache.nul.ie https://cache.nixos.org
        trusted-public-keys = ${lib.my.nix.cacheKey}
      '');

    INSTALLER_SSH_OPTS = "-i .keys/deploy.key";
  };

  packages = with pkgs; [
    coreutils
    nixVersions.stable
    rage
    deploy-rs.deploy-rs
    home-manager
  ];
}
