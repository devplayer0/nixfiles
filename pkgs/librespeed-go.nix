{ lib, fetchFromGitHub, buildGoModule, ... }:
let
  webSrc = fetchFromGitHub {
    owner = "librespeed";
    repo = "speedtest";
    rev = "5.3.0";
    hash = "sha256-OgKGLQcfWX/sBLzaHI6TcJHxX1Wol6K7obLf0+CHrC8=";
  };
in
buildGoModule rec {
  pname = "librespeed-go";
  version = "1.1.5";

  src = fetchFromGitHub {
    owner = "librespeed";
    repo = "speedtest-go";
    rev = "v${version}";
    hash = "sha256-ywGrodl/mj/WB25F0TKVvaV0PV4lgc+KEj0x/ix9HT8=";
  };
  vendorHash = "sha256-ev5TEv8u+tx7xIvNaK8b5iq2XXF6I37Fnrr8mb+N2WM=";

  postInstall = ''
    mkdir -p "$out"/assets
    cp "${webSrc}"/{speedtest.js,speedtest_worker.js,favicon.ico} "$out"/assets/
  '';
}
