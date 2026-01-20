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
      # Explicitly unset fallback DNS (Nix module will not allow for a blank config)
      # TODO: Remove if-else when 26.05 releases
      } // (if config.system.nixos.release == "25.11:u-25.11" then {
        domains = [ config.networking.domain ];
        extraConfig = ''
          FallbackDNS=
          Cache=no-negative
        '';
      } else {
        settings.Resolve = {
          Domains = [ config.networking.domain ];
          FallbackDNS = "";
          Cache = "no-negative";
        };
      });
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
