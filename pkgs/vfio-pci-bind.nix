{ stdenv, kmod, ... }:
stdenv.mkDerivation rec {
  pname = "vfio-pci-bind";
  version = "b41e4545b21de434fc51a34a9bf1d72e3ac66cc8";

  src = fetchGit {
    url = "https://github.com/andre-richter/vfio-pci-bind";
    rev = version;
  };

  prePatch = ''
    substituteInPlace vfio-pci-bind.sh \
      --replace modprobe ${kmod}/bin/modprobe
    substituteInPlace 25-vfio-pci-bind.rules \
      --replace vfio-pci-bind.sh "$out"/bin/vfio-pci-bind.sh
  '';
  installPhase = ''
    mkdir -p "$out"/bin/ "$out"/lib/udev/rules.d
    cp vfio-pci-bind.sh "$out"/bin/
    cp 25-vfio-pci-bind.rules "$out"/lib/udev/rules.d/
  '';
}
