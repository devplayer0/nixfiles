{ lib, ... }:
let
  inherit (builtins) mapAttrs;
  inherit (lib) mkMerge mkDefault;
  inherit (lib.my) net;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.colony) domain prefixes firewallForwards;
  inherit (lib.my.c.nginx) baseHttpConfig proxyHeaders;
in
{
  nixos.systems.git = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      routing = {
        name = "git-vm-routing";
        inherit domain;
        ipv4.address = net.cidr.host 4 prefixes.vms.v4;
      };
      internal = {
        name = "git-vm";
        inherit domain;
        ipv4 = {
          address = net.cidr.host 0 prefixes.vip3;
          mask = 32;
          gateway = null;
          genPTR = false;
        };
        ipv6 = {
          iid = "::4";
          address = net.cidr.host 4 prefixes.vms.v6;
        };
      };
    };

    configuration = { lib, pkgs, modulesPath, config, assignments, allAssignments, ... }:
      let
        inherit (lib) mkMerge;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [
          "${modulesPath}/profiles/qemu-guest.nix"

          ./gitea.nix
          ./gitea-actions.nix
        ];

        config = mkMerge [
          {
            boot = {
              kernelParams = [ "console=ttyS0,115200n8" ];
            };

            fileSystems = {
              "/boot" = {
                device = "/dev/disk/by-label/ESP";
                fsType = "vfat";
              };
              "/nix" = {
                device = "/dev/disk/by-label/nix";
                fsType = "ext4";
              };
              "/persist" = {
                device = "/dev/disk/by-label/persist";
                fsType = "ext4";
                neededForBoot = true;
              };

              "/var/lib/containers" = {
                device = "/dev/disk/by-label/oci";
                fsType = "xfs";
                options = [ "pquota" ];
              };
            };

            users = {
              users = {
                nginx.extraGroups = [ "acme" ];
              };
            };

            security.acme = {
              acceptTerms = true;
              defaults = {
                email = "dev@nul.ie";
                server = "https://acme-v02.api.letsencrypt.org/directory";
                reloadServices = [ "nginx" ];
                dnsResolver = "8.8.8.8";
              };
              certs = {
                "${pubDomain}" = {
                  extraDomainNames = [
                    "*.${pubDomain}"
                  ];
                  dnsProvider = "cloudflare";
                  credentialsFile = config.age.secrets."middleman/cloudflare-credentials.conf".path;
                };
              };
            };

            services = {
              fstrim = lib.my.c.colony.fstrimConfig;
              netdata.enable = true;
              nginx = {
                enable = true;
                enableReload = true;

                logError = "stderr info";
                recommendedTlsSettings = true;
                clientMaxBodySize = "0";
                serverTokens = true;
                sslDhparam = config.age.secrets."dhparams.pem".path;

                # Based on recommended*Settings, but probably better to be explicit about these
                appendHttpConfig = ''
                  ${baseHttpConfig}

                  # caching
                  proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=CACHE:10m inactive=7d max_size=512m;
                '';

                virtualHosts =
                let
                  hosts = {
                    "_" = {
                      default = true;
                      forceSSL = true;
                      onlySSL = false;
                      locations = {
                        "/".root = "${pkgs.nginx}/html";
                      };
                    };

                    "git.${pubDomain}" = {
                      locations."/".proxyPass = "http://localhost:3000";
                    };
                  };

                  defaultsFor = mapAttrs (n: _: {
                    onlySSL = mkDefault true;
                    useACMEHost = mkDefault pubDomain;
                    kTLS = mkDefault true;
                    http2 = mkDefault true;
                  });
                in
                mkMerge [
                  hosts
                  (defaultsFor hosts)
                ];
              };
            };

            virtualisation = {
              podman = {
                enable = true;
              };
              oci-containers = {
                backend = "podman";
              };
              containers.containersConf.settings.network.default_subnet = "10.88.0.0/16";
            };

            systemd.network = {
              links = {
                "10-vms" = {
                  matchConfig.MACAddress = "52:54:00:75:78:a8";
                  linkConfig.Name = "vms";
                };
              };

              networks = {
                "80-vms" = mkMerge [
                  (networkdAssignment "vms" assignments.routing)
                  (networkdAssignment "vms" assignments.internal)
                ];
              };
            };

            my = {
              secrets = {
                key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP+KINpHLMduBuW96JzfSRDLUzkI+XaCBghu5/wHiW5R";
                files = {
                  "dhparams.pem" = {
                    owner = "acme";
                    group = "acme";
                    mode = "440";
                  };
                  "middleman/cloudflare-credentials.conf" = {
                    owner = "acme";
                    group = "acme";
                  };
                };
              };
              server.enable = true;

              firewall = {
                tcp.allowed = [ 19999 "http" "https" ];
                nat.forwardPorts."${allAssignments.estuary.internal.ipv4.address}" = firewallForwards allAssignments;
                extraRules = ''
                  table inet filter {
                    chain forward {
                      ip saddr 10.88.0.0/16 accept
                    }
                  }
                '';
              };
            };
          }
        ];
      };
  };
}
