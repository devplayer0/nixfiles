{ lib, stdenv, fetchFromGitHub, fetchpatch
, meson, ninja, pkg-config, scdoc, wayland-scanner
, wayland, wayland-protocols, libxkbcommon, cairo, gdk-pixbuf, pam
}:

stdenv.mkDerivation rec {
  pname = "swaylock-plugin";
  version = "1dd15b6";

  src = fetchFromGitHub {
    owner = "mstoeckl";
    repo = pname;
    rev = "1dd15b6ecbe91be7a3dc4a0fa9514fb166fb2e07";
    hash = "sha256-xWyDDT8sXAL58HtA9ifzCenKMmOZquzXZaz3ttGGJuY=";
  };

  strictDeps = true;
  depsBuildBuild = [ pkg-config ];
  nativeBuildInputs = [ meson ninja pkg-config scdoc wayland-scanner ];
  buildInputs = [ wayland wayland-protocols libxkbcommon cairo gdk-pixbuf pam ];

  mesonFlags = [
    "-Dpam=enabled" "-Dgdk-pixbuf=enabled" "-Dman-pages=enabled"
  ];
  env.NIX_CFLAGS_COMPILE = "-Wno-maybe-uninitialized";

  meta = with lib; {
    description = "Screen locker for Wayland -- fork with background plugin support";
    longDescription = ''
      Fork of swaylock, a screen locking utility for Wayland compositors.
      With swaylock-plugin, you can for your lockscreen background display
      the animated output from any wallpaper program that implements the
      wlr-layer-shell-unstable-v1 protocol.
    '';
    inherit (src.meta) homepage;
    mainProgram = "swaylock";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = with maintainers; [ devplayer0 ];
  };
}
