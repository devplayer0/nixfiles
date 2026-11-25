{ lib, pkgs, config, ... }:
let
  inherit (lib) flatten optional mkIf mkDefault mkMerge versionAtLeast;
  inherit (lib.my) mkBoolOpt';

  cfg = config.my.network;
in
{
  options.my.network.bbr = mkBoolOpt' false
    ("Whether to use BBR congestion control for TCP connections this box sends. Unlike the default " +
    "(CUBIC), BBR doesn't treat packet loss as congestion, so it keeps throughput up on lossy paths. " +
    "It has no effect on traffic the box forwards.");

  config = mkMerge [
    {
      networking = {
        domain = mkDefault "int.${lib.my.c.pubDomain}";
        useDHCP = false;
        enableIPv6 = mkDefault true;
        useNetworkd = mkDefault true;
      };

      services.resolved = {
        settings.Resolve = {
          Domains = [ config.networking.domain ];
          # Explicitly unset fallback DNS (Nix module will not allow for a blank config)
          FallbackDNS = "";
          Cache = "no-negative";
        };
      };
    }

    (mkIf cfg.bbr {
      # BBR paces its own sending, so the default qdisc (fq_codel) stays as it is. A container's
      # network namespace copies the host's setting only when it's created, so enable this in
      # containers too for it to apply without a restart.
      boot = {
        kernelModules = [ "tcp_bbr" ];
        kernel.sysctl."net.ipv4.tcp_congestion_control" = "bbr";
      };
    })

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
