{ lib, options, config, ... }:
let
  inherit (lib) optionalString concatStringsSep concatMapStringsSep optionalAttrs mkIf mkDefault mkMerge mkOverride;
  inherit (lib.my) parseIPPort mkOpt' mkBoolOpt' dummyOption;

  cfg = config.my.firewall;
in
{
  options.my.firewall = with lib.types; {
    enable = mkBoolOpt' true "Whether to enable the nftables-based firewall.";
    trustedInterfaces = options.networking.firewall.trustedInterfaces;
    tcp = {
      allowed = mkOpt' (listOf (either port str)) [ "ssh" ] "TCP ports to open.";
    };
    udp = {
      allowed = mkOpt' (listOf (either port str)) [ ] "UDP ports to open.";
    };
    extraRules = mkOpt' lines "" "Arbitrary additional nftables rules.";

    nat = with options.networking.nat; {
      enable = mkBoolOpt' true "Whether to enable IP forwarding and NAT.";
      inherit externalInterface forwardPorts;
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      networking = {
        firewall.enable = false;
        nftables = {
          enable = true;
          ruleset =
            let
              trusted' = "{ ${concatStringsSep ", " cfg.trustedInterfaces} }";
            in
            ''
              table inet filter {
                chain wan-tcp {
                  ${concatMapStringsSep "\n    " (p: "tcp dport ${toString p} accept") cfg.tcp.allowed}
                }
                chain wan-udp {
                  ${concatMapStringsSep "\n    " (p: "udp dport ${toString p} accept") cfg.udp.allowed}
                }

                chain wan {
                  ip6 nexthdr icmpv6 icmpv6 type {
                    destination-unreachable,
                    packet-too-big,
                    time-exceeded,
                    parameter-problem,
                    mld-listener-query,
                    mld-listener-report,
                    mld-listener-reduction,
                    nd-router-solicit,
                    nd-router-advert,
                    nd-neighbor-solicit,
                    nd-neighbor-advert,
                    ind-neighbor-solicit,
                    ind-neighbor-advert,
                    mld2-listener-report,
                    echo-request
                  } accept
                  ip protocol icmp icmp type {
                    destination-unreachable,
                    router-solicitation,
                    router-advertisement,
                    time-exceeded,
                    parameter-problem,
                    echo-request
                  } accept
                  ip protocol igmp accept

                  ip protocol tcp tcp flags & (fin|syn|rst|ack) == syn ct state new jump wan-tcp
                  ip protocol udp ct state new jump wan-udp
                }

                chain input {
                  type filter hook input priority 0; policy drop;

                  ct state established,related accept
                  ct state invalid drop

                  iif lo accept
                  ${optionalString (cfg.trustedInterfaces != []) "iifname ${trusted'} accept\n"}
                  jump wan
                }
                chain forward {
                  type filter hook forward priority 0; policy drop;
                  ${optionalString (cfg.trustedInterfaces != []) "\n    iifname ${trusted'} accept\n"}
                  ct state related,established accept
                }
                chain output {
                  type filter hook output priority 0; policy accept;
                }
              }

              table nat {
                chain prerouting {
                  type nat hook prerouting priority 0;
                }

                chain postrouting {
                  type nat hook postrouting priority 100;
                }
              }

              ${cfg.extraRules}
            '';
        };
      };
    }
    (mkIf cfg.nat.enable {
      assertions = [
        {
          assertion = (cfg.nat.forwardPorts != [ ]) -> (cfg.nat.externalInterface != null);
          message = "my.firewall.nat.forwardPorts requires my.firewall.nat.externalInterface";
        }
      ];

      # Yoinked from nixpkgs/nixos/modules/services/networking/nat.nix
      boot = {
        kernel.sysctl = {
          "net.ipv4.conf.all.forwarding" = mkOverride 99 true;
          "net.ipv4.conf.default.forwarding" = mkOverride 99 true;
        } // optionalAttrs config.networking.enableIPv6 {
          # Do not prevent IPv6 autoconfiguration.
          # See <http://strugglers.net/~andy/blog/2011/09/04/linux-ipv6-router-advertisements-and-forwarding/>.
          "net.ipv6.conf.all.accept_ra" = mkOverride 99 2;
          "net.ipv6.conf.default.accept_ra" = mkOverride 99 2;

          # Forward IPv6 packets.
          "net.ipv6.conf.all.forwarding" = mkOverride 99 true;
          "net.ipv6.conf.default.forwarding" = mkOverride 99 true;
        };
      };

      my.firewall.extraRules =
        let
          makeFilter = f:
            let
              ipp = parseIPPort f.destination;
            in
            "ip${optionalString ipp.v6 "6"} daddr ${ipp.ip} ${f.proto} dport ${toString f.sourcePort} accept";
          makeForward = f: "${f.proto} dport ${toString f.sourcePort} dnat to ${f.destination}";
        in
        ''
          table inet filter {
            chain filter-port-forwards {
              ${concatMapStringsSep "\n    " makeFilter cfg.nat.forwardPorts}
            }
            chain forward {
              iifname ${cfg.nat.externalInterface} jump filter-port-forwards
            }
          }

          table nat {
            chain port-forward {
              ${concatMapStringsSep "\n    " makeForward cfg.nat.forwardPorts}
            }
            chain prerouting {
              iifname ${cfg.nat.externalInterface} jump port-forward
            }
          }
        '';
    })
  ]);
}
