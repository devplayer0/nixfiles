{ lib, pkgs, config, ... }:
let
  inherit (lib) flatten optional mkIf mkDefault mkMerge versionAtLeast;
in
{
  config = mkMerge [
    {
      networking = {
        domain = mkDefault "int.${lib.my.c.pubDomain}";
        useDHCP = false;
        enableIPv6 = mkDefault true;
        useNetworkd = mkDefault true;
      };

      services.resolved = {
        domains = [ config.networking.domain ];
        # Explicitly unset fallback DNS (Nix module will not allow for a blank config)
        extraConfig = ''
          FallbackDNS=
          Cache=no-negative
        '';
      };
    }

    (mkIf config.my.build.isDevVM {
      networking.interfaces.eth0.useDHCP = mkDefault true;
      virtualisation = {
        forwardPorts = flatten [
          (optional config.services.openssh.openFirewall { from = "host"; host.port = 2222; guest.port = 22; })
        ];
      };
    })
  ];
}
