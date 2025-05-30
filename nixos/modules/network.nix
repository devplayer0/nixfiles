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

      systemd = {
        additionalUpstreamSystemUnits = mkIf (config.system.nixos.release == "24.12:u-24.11") [
          # TODO: NixOS has its own version of this, but with `network` instead of `networkd`. Is this just a typo? It
          # hasn't been updated in 2 years...
          # This has been done upstream now :)
          # TODO: Remove when 25.05 releases
          "systemd-networkd-wait-online@.service"
        ];
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
