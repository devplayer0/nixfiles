{ lib, pkgs, assignments, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.colony) prefixes custRouting;
in
{
  fileSystems = {
    "/mnt/jam" = {
      device = "/dev/disk/by-label/jam";
      fsType = "ext4";
    };

    "/var/lib/machines/jam" = {
      device = "/mnt/jam";
      options = [ "bind" ];
    };
  };

  systemd = {
    nspawn = {
      jam = {
        enable = true;
        execConfig = {
          Boot = true;
          PrivateUsers = "pick";
          LinkJournal = false;
        };
        networkConfig = {
          Private = true;
          VirtualEthernet = true;
        };
      };
    };
    network.networks = {
      "50-ve-jam" = {
        matchConfig = {
          Kind = "veth";
          Name = "ve-jam";
        };
        address = [
          custRouting.jam-ctr
          prefixes.jam.v6
        ];
        networkConfig = {
          IPv6AcceptRA = false;
          IPv6SendRA = true;
        };
        ipv6Prefixes = [
          {
            Prefix = prefixes.jam.v6;
          }
        ];
        routes = [
          {
            Destination = prefixes.jam.v4;
            Scope = "link";
          }
        ];
      };
    };
    services = {
      "systemd-nspawn@jam" = {
        overrideStrategy = "asDropin";

        serviceConfig = {
          CPUQuota = "400%";
          MemoryHigh = "infinity";
          MemoryMax = "4G";
        };

        wantedBy = [ "machines.target" ];
      };
    };
  };

  my = {
    firewall =
    let
      jamIP = net.cidr.host 0 prefixes.jam.v4;
    in
    {
      nat.forwardPorts."${assignments.internal.ipv4.address}" = [
        {
          port = 60022;
          dst = jamIP;
          dstPort = "ssh";
        }
      ];
      extraRules = ''
        table inet filter {
          chain forward {
            iifname { ve-jam } oifname vms accept
            iifname vms oifname { ve-jam } accept
          }
        }

        table inet nat {
          chain postrouting {
            ip saddr ${jamIP} snat to ${assignments.internal.ipv4.address}
          }
        }
      '';
    };
  };
}
