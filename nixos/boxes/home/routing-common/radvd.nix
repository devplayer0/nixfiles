index: { lib, pkgs, ... }:
let
  inherit (lib) mkForce concatMapStringsSep;
  inherit (lib.my) net;
  inherit (lib.my.c.home) domain prefixes;

  mkInterface = name: ''
    interface lan-${name} {
      AdvSendAdvert on;
      AdvRASrcAddress { fe80::1; };
      AdvLinkMTU ${toString prefixes."${name}".mtu};
      prefix ${prefixes."${name}".v6} {};
      RDNSS ${net.cidr.host 1 prefixes."${name}".v6} ${net.cidr.host 2 prefixes."${name}".v6} {};
      DNSSL ${domain} dyn.${domain} {};
     };
  '';
in
{
  # To be started by keepalived
  systemd.services.radvd.wantedBy = mkForce [ ];

  services = {
    radvd = {
      enable = true;
      config = concatMapStringsSep "\n" mkInterface [ "hi" "lo" "untrusted" ];
    };
  };
}
