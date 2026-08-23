{ pkgs, inputs }:
# Firmware for the OpenWrt boxes. They are not NixOS and are not deployed by this flake - these
# outputs only build a sysupgrade image, which is then flashed by hand (see the box's docs page).
#
# Baking packages into the image is the only reliable way to have them: OpenWrt's package server
# keeps just the current build of each feed, so a box installing packages at runtime is broken as
# soon as the feed moves on from the firmware it is running.
let
  inherit (inputs) openwrt-imagebuilder openwrt-feeds;

  # Fallback to the release branch. Snapshot tracks OpenWrt main, which is where the rtl930x target
  # is actually being developed; the release runs a much older kernel. Both are pinned by
  # `openwrt-feeds`, so neither moves until that input is updated.
  release = "25.12.5";

  mkImage = args: openwrt-imagebuilder.lib.build (args // {
    inherit pkgs;
    cachePath = openwrt-feeds.cachePaths.${args.release};
  });

  # fergal, the 8-port SFP+ switch (XikeStor SKS8300-8X, board-branded ONTi ONT-S508CL-8S)
  fergal = {
    target = "realtek";
    variant = "rtl930x";
    profile = "xikestor_sks8300-8x";
    packages = [ "luci" "ip-full" "ip-bridge" "ethtool-full" ];
  };
in
{
  openwrt-fergal = mkImage (fergal // {
    release = "snapshot";
    # The release feeds do not provide this LuCI app.
    packages = fergal.packages ++ [ "luci-app-sfp-info" ];
  });
  openwrt-fergal-release = mkImage (fergal // { inherit release; });
}
