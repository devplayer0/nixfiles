{ lib, fetchFromGitHub }:
fetchFromGitHub rec {
  pname = "monocraft";
  version = "1.4";

  owner = "IdreesInc";
  repo = pname;
  rev = "v${version}";

  postFetch = ''
    install -Dm444 -t $out/share/fonts/opentype/ $out/Monocraft.otf
    shopt -s extglob dotglob
    rm -rf $out/!(share)
    shopt -u extglob dotglob
  '';
  hash = "sha256-e/kLeYK9//iw+8XOfC0bocldhFGojGApT/EtNtdf4tc=";

  meta = with lib; {
    description = "A programming font based on the typeface used in Minecraft";
    homepage = "https://github.com/${owner}/${repo}";
    license = licenses.ofl;
    platforms = platforms.all;
    maintainers = [ maintainers.devplayer0 ];
  };
}