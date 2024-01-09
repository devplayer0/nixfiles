{ lib
, fetchFromGitHub
, rustPlatform
, pkg-config
, openssl
, libsoup
, dbus
, glib
, glib-networking
, gtk3
, webkitgtk
, libayatana-appindicator
, librsvg
, wrapGAppsHook
, stdenvNoCC
, jq
, moreutils
, nodePackages
, cacert
}:
rustPlatform.buildRustPackage rec {
  pname = "modrinth-app";
  version = "0.6.3";

  src = fetchFromGitHub {
    owner = "modrinth";
    repo = "theseus";
    rev = "v${version}";
    hash = "sha256-gFQXcTqHgSKfne6+v837ENXYYiEYu/Yks9TpnfBCPnA=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "tauri-plugin-single-instance-0.0.0" = "sha256-G4h2OXKPpZMmradutdUWxGG5axL9XMz2ACAe8AQ40eg=";
    };
  };

  nativeBuildInputs = [
    pkg-config
    nodePackages.pnpm
    wrapGAppsHook
  ];
  buildInputs = [
    openssl
    libsoup
    dbus
    glib
    glib-networking
    gtk3
    webkitgtk
    libayatana-appindicator
    librsvg
  ];

  pnpm-deps = stdenvNoCC.mkDerivation {
    pname = "${pname}-pnpm-deps";
    inherit src version;

    sourceRoot = "${src.name}/theseus_gui";

    nativeBuildInputs = [
      jq
      moreutils
      nodePackages.pnpm
      cacert
    ];

    installPhase = ''
      export HOME=$(mktemp -d)
      pnpm config set store-dir $out
      pnpm install --ignore-scripts

      # Remove timestamp and sort the json files
      rm -rf $out/v3/tmp
      for f in $(find $out -name "*.json"); do
        sed -i -E -e 's/"checkedAt":[0-9]+,//g' $f
        jq --sort-keys . $f | sponge $f
      done
    '';

    dontFixup = true;
    outputHashMode = "recursive";
    outputHash = "sha256-9HtTdIotG3sNIlWhd76v7Ia6P69ufp/FFqZfINXSkVc=";
  };

  preBuild = ''
    cd theseus_gui
    export HOME=$(mktemp -d)
    pnpm config set store-dir ${pnpm-deps}
    pnpm install --ignore-scripts --offline
    chmod -R +w node_modules
    pnpm rebuild
    pnpm build
    cd ..
  '';
}
