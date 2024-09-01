{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.colony) domain prefixes qclk;
in
{
  nixos.systems.qclk = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

    assignments = {
      internal = {
        name = "qclk-ctr";
        inherit domain;
        ipv4.address = net.cidr.host 10 prefixes.ctrs.v4;
        ipv6 = {
          iid = "::a";
          address = net.cidr.host 10 prefixes.ctrs.v6;
        };
      };
      qclk = {
        ipv4 = {
          address = net.cidr.host 1 prefixes.qclk.v4;
          gateway = null;
        };
      };
    };

    configuration = { lib, pkgs, config, assignments, ... }:
    let
      inherit (lib) concatStringsSep mkMerge mkIf mkForce;
      inherit (lib.my) networkdAssignment;

      apiPort = 8080;

      instances = [
        {
          host = 2;
          wgKey = "D7z1FhcdxpnrGCE0wBW5PZb5BKuhCu6tcZ/5ZaYxdwQ=";
        }
      ];
      ipFor = i: net.cidr.host i.host prefixes.qclk.v4;
    in
    {
      config = {
        environment = {
          systemPackages = with pkgs; [
            wireguard-tools
          ];
        };

        my = {
          deploy.enable = false;
          server.enable = true;

          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC1kcfvahYmSk8IJKaUIcGkhxf/8Yse2XnU7Qqgcglyq";
            files = {
              "qclk/wg.key" = {
                group = "systemd-network";
                mode = "440";
              };
            };
          };

          firewall = {
            udp.allowed = [ qclk.wgPort ];
            extraRules = ''
              table inet filter {
                chain input {
                  iifname management tcp dport ${toString apiPort} accept
                }
                chain forward {
                  iifname host0 oifname management ip saddr { ${concatStringsSep ", " lib.my.c.as211024.trusted.v4} } accept
                }
              }
              table inet nat {
                chain postrouting {
                  iifname host0 oifname management snat ip to ${assignments.qclk.ipv4.address}
                }
              }
            '';
          };
        };

        systemd = {
          network = {
            netdevs."30-management" = {
              netdevConfig = {
                Name = "management";
                Kind = "wireguard";
              };
              wireguardConfig = {
                PrivateKeyFile = config.age.secrets."qclk/wg.key".path;
                ListenPort = qclk.wgPort;
              };
              wireguardPeers = map (i: {
                PublicKey = i.wgKey;
                AllowedIPs = [ (ipFor i) ];
              }) instances;
            };
            networks = {
              "30-container-host0" = networkdAssignment "host0" assignments.internal;

              "30-management" = networkdAssignment "management" assignments.qclk;
            };
          };
        };

        services = { };
      };
    };
  };
}
