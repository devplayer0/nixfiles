{ lib, config, ... }:
let
  inherit (lib) flatten optional mkIf mkDefault mkMerge;
in
{
  config = mkMerge [
    {
      networking = {
        domain = mkDefault "int.nul.ie";
        useDHCP = false;
        enableIPv6 = mkDefault true;
        useNetworkd = mkDefault true;
      };

      services.resolved.domains = [ config.networking.domain ];
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
