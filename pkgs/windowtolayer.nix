{ lib
, fetchFromGitLab
, rustPlatform
}:
rustPlatform.buildRustPackage rec {
  pname = "windowtolayer";
  version = "a5b89c3c";

  src = fetchFromGitLab {
    domain = "gitlab.freedesktop.org";
    owner = "mstoeckl";
    repo = pname;
    rev = "a5b89c3c047297fd574932860a6c89e9ea02ba5d";
    hash = "sha256-rssL2XkbTqUvJqfUFhzULeE4/VBzjeBC5iZWSJ8MJ+M=";
  };

  cargoHash = "sha256-XHmLsx9qdjlBz4xJFFiO24bR9CMw1o5368K+YMpMIBA=";
}
