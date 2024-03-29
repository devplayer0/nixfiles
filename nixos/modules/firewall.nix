{ lib, options, config, ... }:
let
  inherit (builtins) typeOf attrNames;
  inherit (lib)
    optionalString concatStringsSep concatMapStringsSep mapAttrsToList optionalAttrs mkIf
    mkDefault mkMerge mkOverride;
  inherit (lib.my) isIPv6 mkOpt' mkBoolOpt';

  allowICMP = ''
    icmp type {
      destination-unreachable,
      router-solicitation,
      router-advertisement,
      time-exceeded,
      parameter-problem,
      echo-request
    } accept
  '';
  allowICMP6 = ''
    icmpv6 type {
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
  '';
  allowUDPTraceroute = ''
    udp dport 33434-33625 accept
  '';

  forwardOpts = with lib.types; { config, ... }: {
    options = {
      proto = mkOpt' (enum [ "tcp" "udp" ]) "tcp" "Protocol.";
      port = mkOpt' (either port str) null "Incoming port.";
      dst = mkOpt' str null "Destination IP.";
      dstPort = mkOpt' (either port str) config.port "Destination port.";
    };
  };

  cfg = config.my.firewall;
  iptCfg = config.networking.firewall;
in
{
  options.my.firewall = with lib.types; {
    enable = mkBoolOpt' true "Whether to enable the nftables-based firewall.";
    trustedInterfaces = options.networking.firewall.trustedInterfaces;
    tcp = {
      allowed = mkOpt' (listOf (either port str)) [ ] "TCP ports to open.";
    };
    udp = {
      allowed = mkOpt' (listOf (either port str)) [ ] "UDP ports to open.";
      allowTraceroute = mkBoolOpt' true "Whethor or not to add a rule to accept UDP traceroute packets.";
    };
    extraRules = mkOpt' lines "" "Arbitrary additional nftables rules.";

    nat = with options.networking.nat; {
      enable = mkBoolOpt' true "Whether to enable IP forwarding and NAT.";
      inherit externalInterface;
      forwardPorts = mkOpt' (either (listOf (submodule forwardOpts)) (attrsOf (listOf (submodule forwardOpts)))) [ ] "IPv4 port forwards";
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
              trusted' = "{ ${concatStringsSep ", " (cfg.trustedInterfaces ++ iptCfg.trustedInterfaces)} }";
              openTCP = cfg.tcp.allowed ++ iptCfg.allowedTCPPorts;
              openUDP = cfg.udp.allowed ++ iptCfg.allowedUDPPorts;
            in
            ''
              table inet filter {
                chain wan-tcp {
                  ${concatMapStringsSep "\n    " (p: "tcp dport ${toString p} accept") openTCP}
                  return
                }
                chain wan-udp {
                  ${concatMapStringsSep "\n    " (p: "udp dport ${toString p} accept") openUDP}
                  return
                }

                chain wan {
                  ${allowICMP}
                  ip protocol igmp accept
                  ${allowICMP6}
                  ${allowUDPTraceroute}

                  tcp flags & (fin|syn|rst|ack) == syn ct state new jump wan-tcp
                  meta l4proto udp ct state new jump wan-udp

                  return
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

                  ${allowICMP}
                  ${allowICMP6}
                  ${allowUDPTraceroute}
                }
                chain output {
                  type filter hook output priority 0; policy accept;
                }
              }

              table inet nat {
                chain prerouting {
                  type nat hook prerouting priority dstnat;
                }
                chain output {
                  type nat hook output priority dstnat;
                }
                chain postrouting {
                  type nat hook postrouting priority srcnat;
                }
                chain input {
                  type nat hook input priority srcnat;
                }
              }

              ${cfg.extraRules}
            '';
        };
      };
    }
    (mkIf cfg.nat.enable (
    let
      iifForward = typeOf cfg.nat.forwardPorts == "list" && cfg.nat.forwardPorts != [ ];
      dipForward = typeOf cfg.nat.forwardPorts == "set" && cfg.nat.forwardPorts != { };
    in
    {
      assertions = [
        {
          assertion = with cfg.nat; iifForward -> (externalInterface != null);
          message = "my.firewall.nat.forwardPorts as list requires my.firewall.nat.externalInterface";
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
          inherit (lib.my.nft) natFilterChain dnatChain;
          ipK = ip: "ip${optionalString (isIPv6 ip) "6"}";

          makeFilter = f:
            "${ipK f.dst} daddr ${f.dst} ${f.proto} dport ${toString f.dstPort} accept";
          makeForward = f:
            "${f.proto} dport ${toString f.port} dnat ${ipK f.dst} to ${f.dst}:${toString f.dstPort}";

          dnatJumps = ''
            ${optionalString
              iifForward
              "iifname ${cfg.nat.externalInterface} jump iif-port-forward"}
            ${optionalString
              dipForward
              (concatMapStringsSep "\n    " (ip: "${ipK ip} daddr ${ip} jump ${dnatChain ip}") (attrNames cfg.nat.forwardPorts))}
          '';
        in
        ''
          table inet filter {
            ${optionalString iifForward ''
              chain filter-iif-port-forwards {
                ${concatMapStringsSep "\n    " makeFilter cfg.nat.forwardPorts}
                return
              }
            ''}
            ${optionalString
              dipForward
              (concatStringsSep "\n" (mapAttrsToList (ip: fs: ''
                chain ${natFilterChain ip} {
                  ${concatMapStringsSep "\n    " makeFilter fs}
                  return
                }
              '') cfg.nat.forwardPorts))}

            chain forward {
              ${optionalString
                iifForward
                "iifname ${cfg.nat.externalInterface} jump filter-iif-port-forwards"}
              ${optionalString
                dipForward
                (concatMapStringsSep "\n    " (ip: "jump ${natFilterChain ip}") (attrNames cfg.nat.forwardPorts))}
            }
          }

          table inet nat {
            ${optionalString iifForward ''
              chain iif-port-forward {
                ${concatMapStringsSep "\n    " makeForward cfg.nat.forwardPorts}
                return
              }
            ''}
            ${optionalString
              dipForward
              (concatStringsSep "\n" (mapAttrsToList (ip: fs: ''
                chain ${dnatChain ip} {
                  ${concatMapStringsSep "\n    " makeForward fs}
                  return
                }
              '') cfg.nat.forwardPorts))}

            chain prerouting {
              ${dnatJumps}
            }
            chain output {
              ${dnatJumps}
            }
          }
        '';
    }))
  ]);

  meta.buildDocsInSandbox = false;
}
