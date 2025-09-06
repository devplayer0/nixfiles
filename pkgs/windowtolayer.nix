{ lib
, fetchFromGitLab
, rustPlatform
, python3
, rustfmt
}:
rustPlatform.buildRustPackage rec {
  pname = "windowtolayer";
  version = "97ebd079";

  nativeBuildInputs = [
    python3
    rustfmt
  ];

  src = fetchFromGitLab {
    domain = "gitlab.freedesktop.org";
    owner = "mstoeckl";
    repo = pname;
    rev = "97ebd0790b13bf00afb0c53a768397882fd2e831";
    hash = "sha256-XjbhZEoE5NPBofyJe7OSsE7MWgzjyRjBqiEzaQEuRrU=";
  };

  cargoHash = "sha256-M0BVSUEFGvjgX+vSpwzvaEGs0i80XOTCzvbV4SzYpLc=";
}
