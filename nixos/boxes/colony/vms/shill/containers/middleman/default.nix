{ lib, ... }: {
  nixos.systems.middleman = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "middleman-ctr";
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.ctrs.v4}2";
        ipv6 = {
          iid = "::2";
          address = "${lib.my.colony.start.ctrs.v6}2";
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
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuvP9DEsffop53Fsh7xIdeVyQSF6tSKrOUs2faq6rip";
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
                "cloudflare-credentials.conf" = {
                  owner = "acme";
                  group = "acme";
                };
                "nginx-sso.yaml" = {
                  owner = "nginx-sso";
                  group = "nginx-sso";
                };
              };
            };

            firewall = {
              tcp.allowed = [ "http" "https" 8448 ];
            };

            nginx-sso = {
              enable = true;
              extraConfigFile = config.age.secrets."nginx-sso.yaml".path;
              configuration = {
                listen = {
                  addr = "[::]";
                  port = 8082;
                };
                login = {
                  title = "${lib.my.pubDomain} login";
                  default_redirect = "https://${lib.my.pubDomain}";
                  default_method = "google_oauth";
                  names = {
                    google_oauth = "Google account";
                    simple = "Username / password";
                  };
                };
                cookie = {
                  domain = ".${lib.my.pubDomain}";
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
                    redirect_url = "https://sso.${lib.my.pubDomain}/login";
                    user_id_method = "user-id";
                  };
                };
              };
              includes = {
                endpoint = "http://localhost:8082";
                baseURL = "https://sso.${lib.my.pubDomain}";
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
                server = "https://acme-staging-v02.api.letsencrypt.org/directory";
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
                "${lib.my.pubDomain}" = {
                  extraDomainNames = [
                    "*.${lib.my.pubDomain}"
                  ];
                  dnsProvider = "cloudflare";
                  credentialsFile = config.age.secrets."cloudflare-credentials.conf".path;
                };
              };
            };
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
                access_log /var/log/nginx/access.log combined;

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

                # proxy headers
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

                vhost_traffic_status_zone;
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