{ lib, rustPlatform, callPackage }:
let
  inherit (lib.fileset) toSource unions;
in
rustPlatform.buildRustPackage {
  pname = "slop-broker";
  version = "0.1.0";

  src = toSource {
    root = ./.;
    fileset = unions [ ./Cargo.toml ./Cargo.lock ./src ./tests ./slop-tools.md ];
  };
  cargoLock.lockFile = ./Cargo.lock;

  postInstall = ''
    ln -s slop-broker $out/bin/slop-approve
    install -Dm644 slop-tools.md $out/share/slop-broker/slop-tools.md
  '';

  # Needs KVM, so CI doesn't build it
  passthru.tests.vm = callPackage ./vm-test.nix { };

  meta = {
    description = "Approval broker that runs privileged operations for coding agents";
    license = lib.licenses.mit;
    mainProgram = "slop";
  };
}
