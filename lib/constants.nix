{ lib }:
let
  inherit (lib) concatStringsSep;
in
rec {
  # See https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/misc/ids.nix
  ids = {
    uids = {
      matrix-syncv3 = 400;
      gitea-runner = 401;
      jellyseerr = 402;
      atticd = 403;
      kea = 404;
      keepalived_script = 405;
      photoprism = 406;
    };
    gids = {
      matrix-syncv3 = 400;
      gitea-runner = 401;
      jellyseerr = 402;
      atticd = 403;
      kea = 404;
      keepalived_script = 405;
      photoprism = 406;
      adbusers = 407;
    };
  };

  kernel = {
    lts = pkgs: pkgs.linuxKernel.packages.linux_6_12;
    latest = pkgs: pkgs.linuxKernel.packages.linux_6_13;
  };

  nginx = rec {
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
    baseHttpConfig = ''
      # NixOS provides a logrotate config that auto-compresses :)
      log_format main
        '$remote_addr - $remote_user [$time_local] $scheme "$host" "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"';
      access_log /var/log/nginx/access.log main;

      # optimisation
      sendfile on;
      tcp_nopush on;
      tcp_nodelay on;
      keepalive_timeout 65;

      # gzip
      gzip on;
      gzip_proxied any;
      gzip_comp_level 5;
      gzip_types
        application/atom+xml
        application/javascript
        application/json
        application/xml
        application/xml+rss
        image/svg+xml
        text/css
        text/javascript
        text/plain
        text/xml;
      gzip_vary on;

      # proxying
      proxy_buffering off;
      proxy_redirect off;
      proxy_connect_timeout 60s;
      proxy_read_timeout 60s;
      proxy_send_timeout 60s;
      proxy_http_version 1.1;

      ${proxyHeaders}
    '';
  };

  networkd = {
    noL3 = {
      LinkLocalAddressing = "no";
      DHCP = "no";
      LLDP = false;
      EmitLLDP = false;
      IPv6AcceptRA = false;
    };
  };

  nix = {
    cache = rec {
      substituters = [
        "https://nix-cache.${pubDomain}"
      ];
      keys = [
        "nix-cache.nul.ie-1:BzH5yMfF4HbzY1C977XzOxoPhEc9Zbu39ftPkUbH+m4="
      ];
      conf = ''
        extra-substituters = ${concatStringsSep " " substituters}
        extra-trusted-public-keys = ${concatStringsSep " " keys}
      '';
    };
  };

  pubDomain = "nul.ie";
  colony = rec {
    domain = "ams1.int.${pubDomain}";
    pubV4 = "94.142.240.44";
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
      qclk = {
        v4 = subnet 8 4 all.v4;
      };

      cust = {
        v4 = subnet 8 100 all.v4; # single ip for routing only
        v6 = "2a0e:97c0:4d2:2000::/56";
      };
      mail = {
        v4 = "94.142.241.227/32";
        v6 = subnet 8 0 cust.v6;
      };
      darts = {
        v4 = "94.142.242.255/32";
        v6 = subnet 8 1 cust.v6;
      };
      jam = {
        v4 = subnet 8 4 cust.v4;
        v6 = subnet 8 2 cust.v6;
      };

      vip1 = "94.142.241.224/30";
      vip2 = "94.142.242.254/31";
      vip3 = "94.142.241.117/32";

      as211024 = {
        v4 = subnet 8 50 all.v4;
        v6 = "2a0e:97c0:4df::/64";
      };
      home.v6 = "2a0e:97c0:4d0::/48";
    };

    custRouting = with lib.my.net.cidr; {
      mail-vm = host 1 prefixes.cust.v4;
      darts-vm = host 2 prefixes.cust.v4;
      jam-ctr = host 3 prefixes.cust.v4;
    };

    qclk = {
      wgPort = 51821;
    };

    firewallForwards = aa: [
      {
        port = "http";
        dst = aa.middleman.internal.ipv4.address;
      }
      {
        port = "https";
        dst = aa.middleman.internal.ipv4.address;
      }
      {
        port = 8448;
        dst = aa.middleman.internal.ipv4.address;
      }

      {
        port = 25565;
        dst = aa.simpcraft-oci.internal.ipv4.address;
      }
      {
        port = 25566;
        dst = aa.simpcraft-staging-oci.internal.ipv4.address;
      }
      {
        port = 25567;
        dst = aa.kevcraft-oci.internal.ipv4.address;
      }
      {
        port = 25568;
        dst = aa.kinkcraft-oci.internal.ipv4.address;
      }

      # RCON... unsafe?
      # {
      #   port = 25575;
      #   dst = aa.simpcraft-oci.internal.ipv4.address;
      # }

      {
        port = 2456;
        dst = aa.valheim-oci.internal.ipv4.address;
        proto = "udp";
      }
      {
        port = 2457;
        dst = aa.valheim-oci.internal.ipv4.address;
        proto = "udp";
      }

      {
        port = 41641;
        dst = aa.waffletail.internal.ipv4.address;
        proto = "udp";
      }

      {
        port = 25565;
        dst = aa.simpcraft-oci.internal.ipv4.address;
        proto = "udp";
      }
      {
        port = 25567;
        dst = aa.kevcraft-oci.internal.ipv4.address;
        proto = "udp";
      }
      {
        port = 25568;
        dst = aa.kinkcraft-oci.internal.ipv4.address;
        proto = "udp";
      }

      {
        port = 15636;
        dst = aa.enshrouded-oci.internal.ipv4.address;
        proto = "udp";
      }
      {
        port = 15637;
        dst = aa.enshrouded-oci.internal.ipv4.address;
        proto = "udp";
      }

      {
        port = qclk.wgPort;
        dst = aa.qclk.internal.ipv4.address;
        proto = "udp";
      }
    ];

    fstrimConfig = {
      enable = true;
      # backup happens at 05:00
      interval = "04:45";
    };
  };

  home = rec {
    domain = "h.${pubDomain}";
    vlans = {
      hi = 100;
      lo = 110;
      untrusted = 120;
      wan = 130;
    };
    hiMTU = 9000;
    routers = [
      "river"
      "stream"
    ];
    routersPubV4 = [
      "109.255.108.88"
      "109.255.108.121"
    ];

    prefixes = with lib.my.net.cidr; rec {
      modem = {
        v4 = "192.168.0.0/24";
      };
      all = {
        v4 = "192.168.64.0/18";
        v6 = "2a0e:97c0:4d0::/60";
      };
      core = {
        v4 = subnet 6 0 all.v4;
      };
      hi = {
        v4 = subnet 4 1 all.v4;
        v6 = subnet 4 1 all.v6;
        mtu = hiMTU;
      };
      lo = {
        v4 = subnet 3 1 all.v4;
        v6 = subnet 4 2 all.v6;
        mtu = 1500;
      };
      untrusted = {
        v4 = subnet 6 16 all.v4;
        v6 = subnet 4 3 all.v6;
        mtu = 1500;
      };
      inherit (colony.prefixes) as211024;
    };
    vips = with lib.my.net.cidr; {
      hi = {
        v4 = host (4*256-2) prefixes.hi.v4;
        v6 = host 65535 prefixes.hi.v6;
      };
      lo = {
        v4 = host (8*256-2) prefixes.lo.v4;
        v6 = host 65535 prefixes.lo.v6;
      };
      untrusted = {
        v4 = host 254 prefixes.untrusted.v4;
        v6 = host 65535 prefixes.untrusted.v6;
      };
      as211024 = {
        v4 = host 4 prefixes.as211024.v4;
        v6 = host ((1*65536*65536*65536) + 65535) prefixes.as211024.v6;
      };
    };

    roceBootModules = [ "ib_core" "ib_uverbs" "mlx5_core" "mlx5_ib" ];
  };

  britway = {
    domain = "lon1.int.${pubDomain}";
    pubV4 = "45.76.141.188";
    prefixes = {
      vultr = {
        v6 = "2001:19f0:7402:128b::/64";
      };
      inherit (colony.prefixes) as211024;
    };
    # Need to use this IP as the source address for BGP
    assignedV6 = "2001:19f0:7402:128b:5400:04ff:feac:6e06";
  };

  britnet = {
    domain = "bhx1.int.${pubDomain}";
    pubV4 = "77.74.199.67";
    vpn = {
      port = 51820;
    };
    prefixes = with lib.my.net.cidr; rec {
      vpn = {
        v4 = "10.200.0.0/24";
        v6 = "fdfb:5ebf:6e84::/64";
      };
    };
  };

  tailscale = {
    prefix = {
      v4 = "100.64.0.0/10";
      v6 = "fd7a:115c:a1e0::/48";
    };
  };

  as211024 = rec {
    trusted = {
      v4 = [
        colony.prefixes.as211024.v4
        colony.prefixes.all.v4
        home.prefixes.all.v4
        tailscale.prefix.v4
      ];
      v6 = [
        colony.prefixes.as211024.v6
        colony.prefixes.all.v6
        home.prefixes.all.v6
        tailscale.prefix.v6
      ];
    };
    nftTrust = ''
      iifname as211024 ip saddr { ${concatStringsSep ", " trusted.v4} } accept
      iifname as211024 ip6 saddr { ${concatStringsSep ", " trusted.v6} } accept
    '';
  };

  kelder = {
    groups = {
      storage = 2000;
      media = 2010;
    };

    domain = "hentai.engineer";
    ipv4MTU = 1460;
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
    harmonia = ../.keys/harmonia.pub;
  };
  sshHostKeys = {
    mail-vm = ../.keys/mail-vm-host.pub;
  };
}
