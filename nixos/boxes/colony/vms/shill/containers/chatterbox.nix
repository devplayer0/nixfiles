{ lib, ... }: {
  nixos.systems.chatterbox = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "chatterbox-ctr";
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.ctrs.v4}5";
        ipv6 = {
          iid = "::5";
          address = "${lib.my.colony.start.ctrs.v6}5";
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
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP1ajgIF5V14bf9Zol567k2ieeg1zEd1vJ6gXkydE5UT";
              files."synapse.yaml" = {
                owner = "matrix-synapse";
                group = "matrix-synapse";
              };
            };

            firewall = {
              tcp.allowed = [ 8008 ];
            };
          };

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
          };

          services = {
            matrix-synapse = {
              enable = true;
              withJemalloc = true;

              extraConfigFiles = [ config.age.secrets."synapse.yaml".path ];
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
