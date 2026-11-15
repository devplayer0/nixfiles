{ lib, beam, fetchFromGitHub, ... }:
let
  beamPackages = beam.packages.erlang_29.overrideScope (final: prev: {
    elixir = prev.elixir_1_20;
  });
in
beamPackages.mixRelease rec {
  pname = "paseo-relay";
  version = "0.1.0-unstable-2026-10-28";

  src = fetchFromGitHub {
    owner = "getpaseo";
    repo = "paseo-relay";
    rev = "5f4b7636af41a85ef20200c0b7e99dd1ea2ee1f2";
    hash = "sha256-F4PQg5vU9sI3d9XWukbINdBmhbfcehBzeUVxPKZ06Jg=";
  };

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "mix-deps-${pname}";
    inherit src version;
    hash = "sha256-3J2C4XGqjdM0TYf+Vkv5/AY59tiKLVX81Gxrs9pvKuY=";
  };

  meta = {
    description = "WebSocket relay for Paseo daemons and clients";
    homepage = "https://github.com/getpaseo/paseo-relay";
    license = lib.licenses.asl20;
    mainProgram = "paseo_relay";
  };
}
