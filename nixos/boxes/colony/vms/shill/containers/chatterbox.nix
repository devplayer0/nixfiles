{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.colony) domain prefixes;
in
{
  nixos.systems.chatterbox = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

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
      inherit (lib) genAttrs mkMerge mkIf mkForce;
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
                "chatterbox/doublepuppet.yaml" = {
                  owner = "matrix-synapse";
                  group = "matrix-synapse";
                };

                "chatterbox/mautrix-whatsapp.env" = {
                  owner = "mautrix-whatsapp";
                  group = "mautrix-whatsapp";
                };
                "chatterbox/mautrix-messenger.env" = {
                  owner = "mautrix-meta-messenger";
                  group = "mautrix-meta";
                };
                "chatterbox/mautrix-instagram.env" = {
                  owner = "mautrix-meta-instagram";
                  group = "mautrix-meta";
                };
              };
            };

            firewall = {
              tcp.allowed = [ 19999 8008 8009 ];
            };
          };

          users = with lib.my.c.ids; {
            users = {
              matrix-synapse.extraGroups = [
                "mautrix-whatsapp"
              ];
            };
            groups = { };
          };

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
            services = { } // (genAttrs [ "mautrix-whatsapp" "mautrix-meta-messenger" "mautrix-meta-instagram" ] (_: {
              # ffmpeg needed to convert GIFs to video
              path = with pkgs; [ ffmpeg ];
            }));
          };

          # TODO/FIXME: https://github.com/NixOS/nixpkgs/issues/336052
          nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

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
                web_client_location = "https://element.${pubDomain}";
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
                ] ++ (with lib.my.c.colony.prefixes; [ all.v4 all.v6 ]);
                url_preview_ip_range_whitelist =
                  with allAssignments.middleman.internal;
                  [ ipv4.address ipv6.address ];

                enable_registration = false;
                allow_guest_access = false;

                signing_key_path = config.age.secrets."chatterbox/nul.ie.signing.key".path;

                app_service_config_files = [
                  "/var/lib/heisenbridge/registration.yml"
                  config.age.secrets."chatterbox/doublepuppet.yaml".path
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

            mautrix-whatsapp = {
              enable = true;
              environmentFile = config.age.secrets."chatterbox/mautrix-whatsapp.env".path;
              settings = {
                homeserver = {
                  address = "http://localhost:8008";
                  domain = "nul.ie";
                };
                appservice = {
                  database = {
                    type = "postgres";
                    uri = "$MAU_WAPP_PSQL_URI";
                  };
                  id = "whatsapp2";
                  bot = {
                    username = "whatsapp2";
                    displayname = "WhatsApp Bridge Bot";
                  };
                };
                bridge = {
                  username_template = "wapp2_{{.}}";
                  displayname_template = "{{or .BusinessName .PushName .JID}} (WA)";
                  personal_filtering_spaces = true;
                  delivery_receipts = true;
                  allow_user_invite = true;
                  url_previews = true;
                  command_prefix = "!wa";
                  login_shared_secret_map."nul.ie" = "$MAU_WAPP_DOUBLE_PUPPET_TOKEN";
                  encryption = {
                    allow = true;
                    default = true;
                    require = true;
                  };
                  permissions = {
                    "@dev:nul.ie" = "admin";
                  };
                };
              };
            };

            mautrix-meta.instances = {
              messenger = {
                enable = true;
                registerToSynapse = true;
                dataDir = "mautrix-messenger";
                environmentFile = config.age.secrets."chatterbox/mautrix-messenger.env".path;
                settings = {
                  homeserver = {
                    address = "http://localhost:8008";
                    domain = "nul.ie";
                  };
                  appservice = {
                    database = {
                      type = "postgres";
                      uri = "$MAU_FBM_PSQL_URI";
                    };
                    id = "fbm2";
                    bot = {
                      username = "messenger2";
                      displayname = "Messenger Bridge Bot";
                      avatar = "mxc://maunium.net/ygtkteZsXnGJLJHRchUwYWak";
                    };
                  };
                  network = {
                    mode = "messenger";
                    displayname_template = ''{{or .DisplayName .Username "Unknown user"}} (FBM)'';
                  };
                  bridge = {
                    username_template = "fbm2_{{.}}";
                    personal_filtering_spaces = true;
                    delivery_receipts = true;
                    management_room_text.welcome = "Hello, I'm a Messenger bridge bot.";
                    command_prefix = "!fbm";
                    login_shared_secret_map."nul.ie" = "$MAU_FBM_DOUBLE_PUPPET_TOKEN";
                    backfill = {
                      history_fetch_pages = 5;
                    };
                    encryption = {
                      allow = true;
                      default = true;
                      require = true;
                    };
                    permissions = {
                      "@dev:nul.ie" = "admin";
                    };
                  };
                };
              };

              instagram = {
                enable = true;
                registerToSynapse = true;
                dataDir = "mautrix-instagram";
                environmentFile = config.age.secrets."chatterbox/mautrix-instagram.env".path;
                settings = {
                  homeserver = {
                    address = "http://localhost:8008";
                    domain = "nul.ie";
                  };
                  appservice = {
                    database = {
                      type = "postgres";
                      uri = "$MAU_IG_PSQL_URI";
                    };
                    id = "instagram";
                    bot = {
                      username = "instagram";
                      displayname = "Instagram Bridge Bot";
                      avatar = "mxc://maunium.net/JxjlbZUlCPULEeHZSwleUXQv";
                    };
                  };
                  network = {
                    mode = "instagram";
                    displayname_template = ''{{or .DisplayName .Username "Unknown user"}} (IG)'';
                  };
                  bridge = {
                    username_template = "ig_{{.}}";
                    personal_filtering_spaces = true;
                    delivery_receipts = true;
                    management_room_text.welcome = "Hello, I'm an Instagram bridge bot.";
                    command_prefix = "!ig";
                    login_shared_secret_map."nul.ie" = "$MAU_IG_DOUBLE_PUPPET_TOKEN";
                    backfill = {
                      history_fetch_pages = 5;
                    };
                    encryption = {
                      allow = true;
                      default = true;
                      require = true;
                    };
                    permissions = {
                      "@dev:nul.ie" = "admin";
                      "@adzerq:nul.ie" = "user";
                    };
                  };
                };
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
