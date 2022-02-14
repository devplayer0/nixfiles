{ pkgs, ... }:
{
  # So home-manager will inject the sourcing of ~/.nix-profile/etc/profile.d/nix.sh
  targets.genericLinux.enable = true;

  programs = {
    kakoune.enable = true;
  };
}
