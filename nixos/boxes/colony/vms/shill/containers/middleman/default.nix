{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.colony) domain prefixes;
in
{
  nixos.systems.middleman = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "middleman-ctr";
        inherit domain;
        ipv4.address = net.cidr.host 2 prefixes.ctrs.v4;
        ipv6 = {
          iid = "::2";
          address = net.cidr.host 2 prefixes.ctrs.v6;
        };
      };
    };

    configuration = { lib, pkgs, config, assignments, allAssignments, ... }:
    let
      inherit (lib) mkMerge mkIf;
      inherit (lib.my) networkdAssignment;
    in
    {
      imports = [ ./vhosts.nix ];

      config = mkMerge [
        {
          my = {
            deploy.enable = false;
            server.enable = true;

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAQM9U1e/XcUCyMJITrpAHjAGahpqkZCmtX6pJkYzuks";
              files = {
                "dhparams.pem" = {
                  owner = "acme";
                  group = "acme";
                  mode = "440";
                };
                "pdns-file-records.key" = {
                  owner = "acme";
                  group = "acme";
                };
                "middleman/cloudflare-credentials.conf" = {
                  owner = "acme";
                  group = "acme";
                };
                "middleman/mailcow-ssh.key" = {
                  owner = "acme";
                  group = "acme";
                  mode = "400";
                };
                "middleman/nginx-sso.yaml" = {
                  owner = "nginx-sso";
                  group = "nginx-sso";
                };
                "middleman/htpasswd" = {
                  owner = "nginx";
                  group = "nginx";
                };
              };
            };

            firewall = {
              tcp.allowed = [ "http" "https" 8448 ];
            };

            nginx-sso = {
              enable = true;
              extraConfigFile = config.age.secrets."middleman/nginx-sso.yaml".path;
              configuration = {
                listen = {
                  addr = "[::]";
                  port = 8082;
                };
                login = {
                  title = "${pubDomain} login";
                  default_redirect = "https://${pubDomain}";
                  default_method = "google_oauth";
                  names = {
                    google_oauth = "Google account";
                    simple = "Username / password";
                  };
                };
                cookie = {
                  domain = ".${pubDomain}";
                  secure = true;
                };
                audit_log = {
                  targets = [ "fd://stdout" ];
                  events  = [
                    "access_denied"
                    "login_success"
                    "login_failure"
                    "logout"
                    #"validate"
                  ];
                };
                providers = {
                  simple = {
                    groups = {
                      admin = [ "dev" ];
                    };
                  };
                  google_oauth = {
                    client_id = "545475967061-cag4g1qf0pk33g3pdbom4v69562vboc8.apps.googleusercontent.com";
                    redirect_url = "https://sso.${pubDomain}/login";
                    user_id_method = "user-id";
                  };
                };
              };
              includes = {
                endpoint = "http://localhost:8082";
                baseURL = "https://sso.${pubDomain}";
              };
            };
          };

          users = {
            users = {
              nginx.extraGroups = [ "acme" ];
            };
          };

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
          };

          security = {
            acme = {
              acceptTerms = true;
              defaults = {
                email = "dev@nul.ie";
                #server = "https://acme-staging-v02.api.letsencrypt.org/directory";
                server = "https://acme-v02.api.letsencrypt.org/directory";
                reloadServices = [ "nginx" ];
                dnsResolver = "8.8.8.8";
              };

              certs = {
                "${config.networking.domain}" = {
                  extraDomainNames = [
                    "*.${config.networking.domain}"
                  ];
                  dnsProvider = "exec";
                  credentialsFile =
                  let
                    script = pkgs.writeShellScript "lego-update-int.sh" ''
                      case "$1" in
                      present)
                        cmd=add;;
                      cleanup)
                        cmd=del;;
                      *)
                        exit 1;;
                      esac

                      echo "$@"
                      exec ${pkgs.openssh}/bin/ssh \
                        -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                        -i ${config.age.secrets."pdns-file-records.key".path} \
                        pdns-file-records@estuary-vm "${config.networking.domain}" "$cmd" "$2" "$3"
                    '';
                  in
                  pkgs.writeText "lego-exec-vars.conf" ''
                    EXEC_PROPAGATION_TIMEOUT=60
                    EXEC_POLLING_INTERVAL=2
                    EXEC_PATH=${script}
                  '';
                };
                "${pubDomain}" = {
                  extraDomainNames = [
                    "*.${pubDomain}"
                    "*.s3.${pubDomain}"
                  ];
                  dnsProvider = "cloudflare";
                  credentialsFile = config.age.secrets."middleman/cloudflare-credentials.conf".path;
                  postRun =
                  let
                    sshKey = config.age.secrets."middleman/mailcow-ssh.key".path;
                  in
                  ''
                    ${pkgs.openssh}/bin/scp -i ${sshKey} key.pem fullchain.pem acme@mail.nul.ie:/tmp/
                    ${pkgs.openssh}/bin/ssh -i ${sshKey} acme@mail.nul.ie mailcow-ssl-reload
                  '';
                };
              };
            };
          };

          programs = {
            ssh.knownHostsFiles = [ lib.my.c.sshHostKeys.mail-vm ];
          };

          services = {
            netdata = {
              enable = true;
              configDir = {
                "go.d/nginxvts.conf" = pkgs.writeText "netdata-nginxvts.conf" ''
                  jobs:
                    - name: local
                      url: http://localhost/status/format/json
                '';
              };
            };

            nginx = {
              enable = true;
              enableReload = true;
              additionalModules = with pkgs.nginxModules; [
                vts
                fancyindex
              ];

              recommendedTlsSettings = true;
              clientMaxBodySize = "0";
              serverTokens = true;
              resolver = {
                addresses = [ "[${allAssignments.estuary.base.ipv6.address}]" ];
                valid = "5s";
              };
              proxyResolveWhileRunning = true;
              sslDhparam = config.age.secrets."dhparams.pem".path;

              # Based on recommended*Settings, but probably better to be explicit about these
              appendHttpConfig = ''
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

                ${lib.my.c.nginx.proxyHeaders}

                # caching
                proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=CACHE:10m inactive=7d max_size=4g;

                vhost_traffic_status_zone;

                map $upstream_status $nix_cache_control {
                  "~20(0|6)" "public, max-age=315360000, immutable";
                }
                map $upstream_status $nix_expires {
                  "~20(0|6)" "Thu, 31 Dec 2037 23:55:55 GMT";
                }
              '';
            };
          };
        }
        (mkIf config.my.build.isDevVM {
          virtualisation = {
            forwardPorts = [
              { from = "host"; host.port = 8080; guest.port = 80; }
              { from = "host"; host.port = 8443; guest.port = 443; }
            ];
          };
        })
      ];
    };
  };
}
