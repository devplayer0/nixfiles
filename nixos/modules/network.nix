{ lib, pkgs, config, ... }:
let
  inherit (lib) flatten optional mkIf mkDefault mkMerge;

  # TODO: Backported from systemd 251
  networkd-wait-online-at = pkgs.writeTextDir "lib/systemd/system/systemd-networkd-wait-online@.service" ''
    #  SPDX-License-Identifier: LGPL-2.1-or-later
    #
    #  This file is part of systemd.
    #
    #  systemd is free software; you can redistribute it and/or modify it
    #  under the terms of the GNU Lesser General Public License as published by
    #  the Free Software Foundation; either version 2.1 of the License, or
    #  (at your option) any later version.

    [Unit]
    Description=Wait for Network Interface %i to be Configured
    Documentation=man:systemd-networkd-wait-online.service(8)
    DefaultDependencies=no
    Conflicts=shutdown.target
    Requires=systemd-networkd.service
    After=systemd-networkd.service
    Before=network-online.target shutdown.target

    [Service]
    Type=oneshot
    ExecStart=${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online -i %i
    RemainAfterExit=yes

    [Install]
    WantedBy=network-online.target
  '';
in
{
  config = mkMerge [
    {
      networking = {
        domain = mkDefault "int.${lib.my.pubDomain}";
        useDHCP = false;
        enableIPv6 = mkDefault true;
        useNetworkd = mkDefault true;
      };

      systemd = {
        packages = [ networkd-wait-online-at ];
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
