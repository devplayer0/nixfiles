{ lib }: rec {
  nginx = {
    proxyHeaders = ''
      # Setting any proxy_header in a child (e.g. location) will nuke the parents...
      proxy_set_header X-Origin-URI $request_uri;
      proxy_set_header Host $host;
      proxy_set_header X-Host $http_host;
      proxy_set_header X-Forwarded-Host $http_host;
      proxy_set_header X-Forwarded-Server $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Protocol $scheme;
      proxy_set_header X-Scheme $scheme;
    '';
  };

  nix = {
    cacheKeys = [
      "nix-cache.nul.ie-1:XofkqdHQSGFoPjB6aRohQbCU2ILKFqhNjWfoOdQgF5Y="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  pubDomain = "nul.ie";
  colony = {
    domain = "ams1.int.${pubDomain}";
    prefixes = with lib.my.net.cidr; rec {
      all = {
        v4 = "10.100.0.0/16";
        v6 = "2a0e:97c0:4d2:10::/60";
      };
      base = {
        v4 = subnet 8 0 all.v4;
        v6 = subnet 4 0 all.v6;
      };
      vms = {
        v4 = subnet 8 1 all.v4;
        v6 = subnet 4 1 all.v6;
      };
      ctrs = {
        v4 = subnet 8 2 all.v4;
        v6 = subnet 4 2 all.v6;
      };
      oci = {
        v4 = subnet 8 3 all.v4;
        v6 = subnet 4 3 all.v6;
      };

      cust = {
        v4 = subnet 8 100 all.v4; # single ip for routing only
        v6 = "2a0e:97c0:4d2:2000::/56";
      };
      mail = {
        v4 = "94.142.241.227/32";
        v6 = subnet 8 0 cust.v6;
      };

      vip1 = "94.142.241.224/30";
      vip2 = "94.142.242.254/31";
    };
    fstrimConfig = {
      enable = true;
      # backup happens at 05:00
      interval = "04:45";
    };
  };
  kelder = {
    groups = {
      storage = 2000;
      media = 2010;
    };

    domain = "hentai.engineer";
    vpn = {
      port = 51820;
    };
    prefixes = with lib.my.net.cidr; rec {
      all.v4 = "172.16.64.0/20";
      ctrs.v4 = subnet 4 0 all.v4;
    };
  };
  sshKeyFiles = {
    me = ../.keys/me.pub;
    deploy = ../.keys/deploy.pub;
    rsyncNet = ../.keys/zh2855.rsync.net.pub;
    mailcowAcme = ../.keys/mailcow-acme.pub;
  };
  sshHostKeys = {
    mail-vm = ../.keys/mail-vm-host.pub;
  };
}
