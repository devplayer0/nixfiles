{ lib, pkgs, config, assignments, allAssignments, ... }: {
  config = {
    systemd = {
      services = {
        # systemd-networkd doesn't support tc filtering
        wan-filter-to-ifb =
        let
          waitOnline = [
            "systemd-networkd-wait-online@wan.service"
            "systemd-networkd-wait-online@ifb-wan.service"
          ];
        in
        {
          description = "Install tc filter to pass WAN traffic to IFB";
          enable = true;
          bindsTo = waitOnline;
          after = waitOnline;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ${pkgs.iproute2}/bin/tc filter add dev wan parent ffff: u32 match u32 0 0 action mirred egress redirect dev ifb-wan
          '';
          wantedBy = [ "multi-user.target" ];
        };

        bandwidth-limiter =
        let
          deps = [ "wan-filter-to-ifb.service" ];
        in
        {
          description = "WAN bandwidth limiter";
          enable = true;
          bindsTo = deps;
          after = deps;
          path = with pkgs; [ python310 iproute2 ];
          environment = {
            PYTHONUNBUFFERED = "1";
          };
          serviceConfig = {
            ExecStart = [ "${./bandwidth.py} wan,ifb-wan 245 10000" ];
            StateDirectory = "bandwidth-limiter";
          };
          wantedBy = [ "multi-user.target" ];
        };
      };

      network = {
        netdevs = {
          "25-ifb-wan".netdevConfig = {
            Name = "ifb-wan";
            Kind = "ifb";
          };
        };

        networks = {
          "80-wan" = {
            extraConfig = ''
              [QDisc]
              Parent=ingress
              Handle=ffff

              # Outbound traffic limiting
              [TokenBucketFilter]
              Parent=root
              LatencySec=0.3
              BurstBytes=512K
              # *bits
              Rate=245M
            '';
          };
          "80-ifb-wan" = {
            matchConfig.Name = "ifb-wan";
            extraConfig = ''
              # Inbound traffic limiting
              [TokenBucketFilter]
              Parent=root
              LatencySec=0.3
              BurstBytes=512K
              # *bits
              Rate=245M
            '';
          };
        };
      };
    };

    my = {
      tmproot.persistence.config.directories = [ "/var/lib/bandwidth-limiter" ];
    };
  };
}
