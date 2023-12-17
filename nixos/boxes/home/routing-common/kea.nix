index: { lib, pkgs, assignments, ... }:
let
  inherit (lib) mkForce;
  inherit (lib.my) net;
  inherit (lib.my.c.home) domain prefixes vips hiMTU;

  dns-servers = [
    {
      ip-address = net.cidr.host 1 prefixes.core.v4;
      port = 5353;
    }
    {
      ip-address = net.cidr.host 2 prefixes.core.v4;
      port = 5353;
    }
  ];
in
{
  users = with lib.my.c.ids; {
    users.kea= {
      isSystemUser = true;
      uid = uids.kea;
      group = "kea";
    };
    groups.kea.gid = gids.kea;
  };

  systemd.services = {
    kea-dhcp4-server.serviceConfig.DynamicUser = mkForce false;
    kea-dhcp-ddns-server.serviceConfig.DynamicUser = mkForce false;
  };

  services = {
    kea = {
      dhcp4 = {
        enable = true;
        settings = {
          interfaces-config = {
            interfaces = [
              "lan-hi/${assignments.hi.ipv4.address}"
              "lan-lo/${assignments.lo.ipv4.address}"
              "lan-untrusted/${assignments.untrusted.ipv4.address}"
            ];
          };
          lease-database = {
            type = "memfile";
            persist = true;
            name = "/var/lib/kea/dhcp.leases";
          };

          option-data = [
            {
              name = "domain-name";
              data = domain;
            }
            {
              name = "domain-search";
              data = "${domain}, dyn.${domain}";
              always-send = true;
            }
          ];
          subnet4 = [
            {
              id = 1;
              subnet = prefixes.hi.v4;
              interface = "lan-hi";
              option-data = [
                {
                  name = "routers";
                  data = vips.hi.v4;
                }
                {
                  name = "domain-name-servers";
                  data = "${net.cidr.host 1 prefixes.hi.v4}, ${net.cidr.host 2 prefixes.hi.v4}";
                }
                {
                  name = "interface-mtu";
                  data = toString hiMTU;
                }
              ];
              pools = [
                {
                  pool = if index == 0
                    then "192.168.68.120 - 192.168.69.255"
                    else "192.168.70.0 - 192.168.71.240";
                }
              ];
              reservations = [
                {
                  # castle
                  hw-address = "24:8a:07:a8:fe:3a";
                  ip-address = net.cidr.host 40 prefixes.hi.v4;
                }
              ];
            }
            {
              id = 2;
              subnet = prefixes.lo.v4;
              interface = "lan-lo";
              option-data = [
                {
                  name = "routers";
                  data = vips.lo.v4;
                }
                {
                  name = "domain-name-servers";
                  data = "${net.cidr.host 1 prefixes.lo.v4}, ${net.cidr.host 2 prefixes.lo.v4}";
                }
              ];
              pools = [
                {
                  pool = if index == 0
                    then "192.168.72.120 - 192.168.75.255"
                    else "192.168.76.0 - 192.168.79.240";
                }
              ];
              reservations = [
                {
                  # castle
                  hw-address = "24:8a:07:a8:fe:3a";
                  ip-address = net.cidr.host 40 prefixes.lo.v4;
                }
              ];
            }
          ];
          ddns-send-updates = true;
          ddns-replace-client-name = "when-not-present";
          ddns-qualifying-suffix = "dyn.${domain}";
          ddns-generated-prefix = "ip";
          ddns-update-on-renew = true;

          dhcp-ddns.enable-updates = true;
        };
      };

      dhcp-ddns = {
        enable = true;
        settings = {
          forward-ddns.ddns-domains = [
            {
              name = "dyn.${domain}.";
              inherit dns-servers;
            }
          ];
        };
      };
    };
  };
}
