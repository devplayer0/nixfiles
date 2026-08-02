index: { lib, pkgs, ... }:
let
  inherit (lib) mkForce concatMapStringsSep concatStringsSep;
  inherit (lib.my) net;
  inherit (lib.my.c.home) domain searchDomains prefixes vips;

  # untrusted uses external (Cloudflare) resolvers, matching the v4 kea config;
  # trusted VLANs use the internal recursor via its floating VRRP VIP
  rdnss = name:
    if name == "untrusted"
    then "2606:4700:4700::1111 2606:4700:4700::1001"
    else vips."${name}".v6;

  mkInterface = name: ''
    interface lan-${name} {
      AdvSendAdvert on;
      AdvRASrcAddress { fe80::1; };
      AdvLinkMTU ${toString prefixes."${name}".mtu};
      prefix ${prefixes."${name}".v6} {};
      RDNSS ${rdnss name} {};
      DNSSL ${concatStringsSep " " searchDomains} {};
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
