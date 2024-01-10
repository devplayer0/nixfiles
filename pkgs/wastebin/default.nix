{ lib
, fetchFromGitHub
, rustPlatform
}:
rustPlatform.buildRustPackage rec {
  pname = "wastebin";
  version = "2.4.2";

  src = fetchFromGitHub {
    owner = "matze";
    repo = pname;
    rev = version;
    hash = "sha256-9SsNtIZfRK9HwWaqlsuSCs7eNK/7KnzDtCe0fFslXwA=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "rusqlite_migration-1.1.0" = "sha256-FpIwgISYWEg7IQxG4tJ3u6b8+qanaqanZrq0Bz5WlLs=";
    };
  };
}
