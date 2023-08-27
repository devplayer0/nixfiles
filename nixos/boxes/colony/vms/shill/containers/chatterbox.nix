{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.colony) domain prefixes;
in
{
  nixos.systems.chatterbox = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "chatterbox-ctr";
        inherit domain;
        ipv4.address = net.cidr.host 5 prefixes.ctrs.v4;
        ipv6 = {
          iid = "::5";
          address = net.cidr.host 5 prefixes.ctrs.v6;
        };
      };
    };

    configuration = { lib, pkgs, config, assignments, allAssignments, ... }:
    let
      inherit (lib) mkMerge mkIf;
      inherit (lib.my) networkdAssignment;
    in
    {
      config = mkMerge [
        {
          my = {
            deploy.enable = false;
            server.enable = true;

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGGx50oGzm5TsaB5R6f/daFPc5QNkmM15uc9/kiBxKaY";
              files = {
                "chatterbox/synapse.yaml" = {
                  owner = "matrix-synapse";
                  group = "matrix-synapse";
                };
                "chatterbox/nul.ie.signing.key" = {
                  owner = "matrix-synapse";
                  group = "matrix-synapse";
                };
              };
            };

            firewall = {
              tcp.allowed = [ 19999 8008 ];
            };
          };

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
          };

          services = {
            netdata.enable = true;
            matrix-synapse = {
              enable = true;
              withJemalloc = true;
              extras = [
                "oidc"
              ];

              extraConfigFiles = [ config.age.secrets."chatterbox/synapse.yaml".path ];
              settings = {
                server_name = "nul.ie";
                public_baseurl = "https://matrix.nul.ie";
                admin_contact = "dev@nul.ie";
                prescence.enabled = true;

                listeners = [
                  {
                    # Covers both IPv4 and IPv6
                    bind_addresses = [ "::" ];
                    port = 8008;
                    type = "http";
                    tls = false;
                    x_forwarded = true;
                    resources = [
                      {
                        compress = false;
                        names = [ "client" "federation" ];
                      }
                    ];
                  }
                  {
                    bind_addresses = [ "127.0.0.1" "::1" ];
                    port = 9000;
                    type = "manhole";

                    # The NixOS module has defaults for these that we need to override since they don't make sense here
                    tls = false;
                    resources = [];
                  }
                ];
                # Even public options must be in the secret file because options are only merged at the top level.
                # Let's just override the defaults in the base config to keep Nix happy
                database = {
                  name = "sqlite3";
                  args.database = "/dev/null";
                };

                #media_store_path = "/var/lib/synapse-media";
                max_upload_size = "1024M";
                dynamic_thumbnails = true;
                url_preview_enabled = true;
                url_preview_ip_range_blacklist = [
                  "127.0.0.0/8"
                  "10.0.0.0/8"
                  "172.16.0.0/12"
                  "192.168.0.0/16"
                  "100.64.0.0/10"
                  "192.0.0.0/24"
                  "169.254.0.0/16"
                  "192.88.99.0/24"
                  "198.18.0.0/15"
                  "192.0.2.0/24"
                  "198.51.100.0/24"
                  "203.0.113.0/24"
                  "224.0.0.0/4"

                  "::1/128"
                  "fe80::/10"
                  "fc00::/7"
                  "2001:db8::/32"
                  "ff00::/8"
                  "fec0::/10"
                ] ++ (with lib.my.colony.prefixes; [ all.v4 all.v6 ]);
                url_preview_ip_range_whitelist =
                  with allAssignments.middleman.internal;
                  [ ipv4.address ipv6.address ];

                enable_registration = false;
                allow_guest_access = false;

                signing_key_path = config.age.secrets."chatterbox/nul.ie.signing.key".path;

                app_service_config_files = [
                  "/var/lib/heisenbridge/registration.yml"
                ];
              };
            };

            heisenbridge = {
              enable = true;
              homeserver = "http://localhost:8008";
              owner = "@dev:nul.ie";
              namespaces = {
                users = [
                  {
                    exclusive = true;
                    regex = "@irc_.*";
                  }
                ];
              };
            };
          };
        }
        (mkIf config.my.build.isDevVM {
          virtualisation = {
            forwardPorts = [
              { from = "host"; host.port = 8080; guest.port = 80; }
            ];
          };
        })
      ];
    };
  };
}
