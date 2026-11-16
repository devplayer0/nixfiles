{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.home) domain prefixes vips vlanDns hiMTU;
in
{
  nixos.systems.slop-cannon = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";
    rendered = config.configuration.config.my.asContainer;

    assignments = {
      hi = {
        name = "slop-cannon-ctr";
        inherit domain;
        mtu = hiMTU;
        ipv4 = {
          address = net.cidr.host 104 prefixes.hi.v4;
          mask = 22;
          gateway = vips.hi.v4;
        };
        ipv6 = {
          iid = "::5:4";
          address = net.cidr.host (65536*5+4) prefixes.hi.v6;
        };
      };
    };

    configuration = { lib, config, pkgs, inputs, assignments, ... }:
    let
      inherit (builtins) toJSON;
      inherit (lib) mkMerge;
      inherit (lib.my) networkdAssignment;

      agentUser = "slop-cannon";
      agentHome = "/home/${agentUser}";

      # TODO: Drop once Codex recognises bubblewrap's newer `/proc` error wording.
      # Restore the diagnostic its procfs preflight expects so it uses its container fallback.
      codexBubblewrap = pkgs.bubblewrap.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace bubblewrap.c \
            --replace-fail "Can't mount proc on %s" "Can't mount proc on /newroot%s"
        '';
      });

      # Steer agents to the approval broker; these match command text, so they aren't a boundary
      claudeDeny = [
        "Bash(deploy:*)"
        "Bash(ssh-machine:*)"
        "Read(**/.keys/**)"
        "Edit(**/.keys/**)"
      ];
      claudeAsk = [
        "Bash(slop-deploy:*)"
        "Bash(slop-ssh:*)"
      ];

      slopClone = pkgs.writeShellApplication {
        name = "slop-clone";
        runtimeInputs = with pkgs; [ jujutsu openssh paseo ];
        text = ''
          if [ $# -ne 1 ] || [[ "$1" != */* ]]; then
            echo "usage: slop-clone <owner>/<repo>" >&2
            exit 1
          fi
          repo="$1"
          dest="$HOME/src/''${repo##*/}"

          if ! jj git clone --colocate "git@git.nul.ie:$repo.git" "$dest"; then
            echo >&2
            echo "Clone failed. If Gitea refused the key, add it as a write-enabled deploy key on $repo:" >&2
            cat "$HOME/.ssh/id_ed25519.pub" >&2
            exit 1
          fi

          paseo workspace create --isolation local --path "$dest"
        '';
      };
    in
    {
      config = {
        my = {
          deploy.enable = false;
          server.enable = true;

          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILWhNyGER3E0cgpsl6eIiG1mJFcS6hckU74t9vzMY4Le";
            files = {
              # `PASEO_PASSWORD=...`
              "slop-cannon/paseo.env" = { };
            };
          };

          tmproot.persistence.config.directories = [
            {
              directory = agentHome;
              user = agentUser;
              group = agentUser;
              mode = "0700";
            }
          ];
        };

        users = with lib.my.c.ids; {
          groups.${agentUser}.gid = gids.slop-cannon;
          users.${agentUser} = {
            isNormalUser = true;
            uid = uids.slop-cannon;
            group = agentUser;
            hashedPassword = "!";
            shell = pkgs.fish;
            openssh.authorizedKeys.keyFiles = [ lib.my.c.sshKeyFiles.me ];
          };
        };

        home-manager.users.${agentUser} = {
          my.agents.enable = true;

          home.packages = [ slopClone codexBubblewrap ];

          programs = {
            claude-code.settings.permissions = {
              deny = claudeDeny;
              ask = claudeAsk;
            };
            codex.settings.cli_auth_credentials_store = "file";

            # The shared config pins `IdentityFile` for every host
            ssh.settings."git.nul.ie" = {
              IdentityFile = [ "~/.ssh/id_ed25519" ];
            };
          };
        };

        # Managed settings can't be edited by agents (unlike `~/.claude`)
        environment.etc."claude-code/managed-settings.json".text = toJSON {
          permissions = {
            disableBypassPermissionsMode = "disable";
            deny = claudeDeny;
          };
        };

        systemd = {
          network.networks."80-container-host0" = mkMerge [
            (networkdAssignment "host0" assignments.hi)
            { networkConfig = vlanDns "hi"; }
          ];

          services = {
            # Box-wide key for Gitea deploy keys
            slop-cannon-ssh-key = {
              description = "Generate ${agentUser}'s SSH key";
              wantedBy = [ "multi-user.target" ];
              unitConfig.RequiresMountsFor = agentHome;
              path = [ pkgs.openssh ];
              script = ''
                if [ ! -e ~/.ssh/id_ed25519 ]; then
                  install -d -m 700 ~/.ssh
                  ssh-keygen -q -t ed25519 -N "" -C "${agentUser}@${config.networking.hostName}" -f ~/.ssh/id_ed25519
                fi
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = agentUser;
              };
            };

            paseo = {
              unitConfig.RequiresMountsFor = agentHome;
              serviceConfig.EnvironmentFile = config.age.secrets."slop-cannon/paseo.env".path;
              # Don't interrupt running agents on deploy; restart by hand when convenient
              restartIfChanged = false;
            };
          };
        };

        services.paseo = {
          enable = true;
          package = pkgs.paseo;
          user = agentUser;
          group = agentUser;
          listenAddress = "127.0.0.1";
          port = 6767;

          relay = {
            enable = true;
            mode = "remote";
            host = "paseo-relay.${lib.my.c.pubDomain}";
            port = 443;
            useTls = true;
          };

          # Rewritten on every start, so changes made from the app don't survive a restart
          settings = {
            version = 1;
            # Pairing links open our copy of the web app (served by `middleman`)
            app.baseUrl = "https://paseo.${lib.my.c.pubDomain}";
            daemon = {
              # Keep agents from changing modes, answering prompts or opening terminals
              mcp.injectIntoAgents = false;
              relay.requireProtectedSecurity = true;
              agentProfiles = [
                {
                  id = "claude-accept-edits";
                  name = "Claude, accept edits";
                  provider = "claude";
                  modeId = "acceptEdits";
                }
              ];
            };
            # Avoids downloading the local speech model
            features = {
              dictation.enabled = false;
              voiceMode.enabled = false;
            };
            agents.providers = lib.genAttrs
              [ "copilot" "opencode" "pi" "omp" "antigravity" "muse" ]
              (_: { enabled = false; });
            log.file.level = "info";
          };
        };
      };
    };
  };
}
