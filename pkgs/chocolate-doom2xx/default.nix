{ lib, stdenv, autoreconfHook, pkg-config, SDL, SDL_mixer, SDL_net
, fetchFromGitHub, fetchpatch, python3 }:

stdenv.mkDerivation rec {
  pname = "chocolate-doom";
  version = "2.3.0";

  src = fetchFromGitHub {
    owner = "chocolate-doom";
    repo = pname;
    rev = "${pname}-${version}";
    sha256 = "sha256-1uw/1CYKBvDNgT5XxRBY24Evt3f4Y6YQ6bScU+KNHgM=";
  };

  patches = [
    # Pull upstream patch to fix build against gcc-10:
    #   https://github.com/chocolate-doom/chocolate-doom/pull/1257
    (fetchpatch {
      name = "fno-common.patch";
      url = "https://github.com/chocolate-doom/chocolate-doom/commit/a8fd4b1f563d24d4296c3e8225c8404e2724d4c2.patch";
      sha256 = "1dmbygn952sy5n8qqp0asg11pmygwgygl17lrj7i0fxa0nrhixhj";
    })
    ./demoloopi.patch
  ];

  outputs = [ "out" "man" ];

  postPatch = ''
    patchShebangs --build man/{simplecpp,docgen}
  '';

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    # for documentation
    python3
  ];
  buildInputs = [ (SDL.override { cacaSupport = true; }) SDL_mixer SDL_net ];
  enableParallelBuilding = true;

  meta = {
    homepage = "http://chocolate-doom.org/";
    description = "A Doom source port that accurately reproduces the experience of Doom as it was played in the 1990s";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.unix;
    hydraPlatforms = lib.platforms.linux; # darwin times out
    maintainers = with lib.maintainers; [ ];
  };
}
