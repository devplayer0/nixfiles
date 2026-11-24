{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.home) domain prefixes vips;
in
{
  nixos.systems.slop-cannon = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    # The routers limit traffic from the untrusted VLAN to the Internet
    assignments.untrusted = {
      inherit domain;
      mtu = prefixes.untrusted.mtu;
      ipv4 = {
        address = net.cidr.host 5 prefixes.untrusted.v4;
        mask = 24;
        gateway = vips.untrusted.v4;
      };
      ipv6 = {
        iid = "::5";
        address = net.cidr.host 5 prefixes.untrusted.v6;
      };
    };

    configuration = { lib, modulesPath, config, pkgs, assignments, ... }:
    let
      inherit (builtins) toJSON;
      inherit (lib) mkMerge;
      inherit (lib.my) networkdAssignment;

      agentUser = "slop-cannon";
      agentHome = "/home/${agentUser}";
      # The bot user's access token, for Git over HTTPS and Gitea's API
      giteaToken = config.age.secrets."slop-cannon/gitea-token".path;
      giteaUrl = "https://git.nul.ie";
      paseoPasswordFile = config.age.secrets."slop-cannon/paseo.env".path;

      # Steer agents to the approval broker; these match command text, so they aren't a boundary.
      # `.keys/` only has the committed public keys here, which agents may read.
      claudeDeny = [
        "Bash(deploy:*)"
        "Bash(ssh-machine:*)"
      ];
      # The broker asks a human where policy says so; a second prompt here would only add noise
      claudeAllow = [ "Bash(slop:*)" ];

      # Gitea takes a token as the username when the password is `x-oauth-basic`
      gitCredential = pkgs.writeShellScript "gitea-credential" ''
        [ "$1" = get ] || exit 0
        printf 'username=%s\npassword=x-oauth-basic\n' "$(cat ${giteaToken})"
      '';

      # `tea`, logged in as the bot
      tea = pkgs.writeShellScriptBin "tea" ''
        GITEA_INSTANCE_URL=${giteaUrl} GITEA_TOKEN="$(cat ${giteaToken})" exec ${pkgs.tea}/bin/tea "$@"
      '';

      giteaRule = ''
        # Pull requests

        By default, your work reaches Dev as a pull request on Gitea (`${giteaUrl}`), and Dev
        merges it. The task or the repository's own instructions (its `AGENTS.md`) can say
        otherwise, for example that you may push to its main branch yourself; follow them.

        - When a piece of work is done, push it to a branch of its own and open a pull request.
          Name the branch after the work, such as `fix-paseo-relay`.
        - Push with jj: `jj bookmark set <branch> -r <revision>` then `jj git push -b <branch>`.
          With Git: `git push origin HEAD:refs/heads/<branch>`.
        - Open the pull request with `tea`, which is already logged in, as a bot user:
          `tea pulls create --head <branch> --title "<summary>" --description "<what and why>"`.
          Pass `--head`, since a jj checkout has no current branch. Outside a clone, add
          `--repo <owner>/<repo>`.
        - To update a pull request, push to its branch again; rewriting its commits is fine.
        - Read a pull request and its comments with `tea pulls <index> --comments`, and reply with
          `tea comment <index> "<text>"`.
        - The repository's commit conventions still apply.
      '';

      slopClone = pkgs.writeShellApplication {
        name = "slop-clone";
        runtimeInputs = with pkgs; [ git jujutsu paseo ];
        text = ''
          if [ $# -ne 1 ] || [[ "$1" != */* ]]; then
            echo "usage: slop-clone <owner>/<repo>" >&2
            exit 1
          fi
          repo="$1"
          dest="$HOME/src/''${repo##*/}"

          if ! jj git clone --colocate "${giteaUrl}/$repo.git" "$dest"; then
            echo >&2
            echo "Clone failed. If Gitea refused, add the bot user to $repo as a collaborator with Write." >&2
            exit 1
          fi

          paseo workspace create --isolation local --path "$dest"
        '';
      };

      slopPair = pkgs.writeShellApplication {
        name = "slop-pair";
        runtimeInputs = [ pkgs.paseo ];
        text = ''
          if [ "$#" -ne 0 ]; then
            echo "usage: slop-pair" >&2
            exit 2
          fi

          paseo daemon pair
          printf '\n'
          exec doas ${pkgs.coreutils}/bin/cat ${paseoPasswordFile}
        '';
      };
    in
    {
      imports = [
        "${modulesPath}/profiles/qemu-guest.nix"
      ];

      config = {
        boot = {
          # Load the passed-through ConnectX VF even when PCI probing doesn't autoload it.
          kernelModules = [ "kvm-amd" "mlx5_core" ];
          kernelParams = [ "console=ttyS0,115200n8" ];
          initrd = {
            availableKernelModules = [ "virtio_pci" "ahci" "sr_mod" "virtio_blk" ];
            kernelModules = [ "dm-snapshot" ];
          };
          # On disk rather than in the tmpfs root, so agents' scratch files don't use RAM
          tmp.cleanOnBoot = true;
        };

        hardware = {
          enableRedistributableFirmware = true;
        };

        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-partlabel/esp";
            fsType = "vfat";
          };
          "/nix" = {
            device = "/dev/main/slop-cannon-nix";
            fsType = "ext4";
          };
          "/persist" = {
            device = "/dev/main/slop-cannon-persist";
            fsType = "ext4";
            neededForBoot = true;
          };
          "/tmp" = {
            device = "/dev/main/slop-cannon-tmp";
            fsType = "ext4";
            # Return deleted scratch space to the thin pool straight away
            options = [ "discard" ];
          };
        };

        networking = { inherit domain; };

        services = {
          # The LVs are thin, so space moves between them as needed
          lvm = {
            boot.thin.enable = true;
            dmeventd.enable = true;
          };
          fstrim.enable = true;
        };

        # Grow the pool into the VG's spare space before it fills
        environment.etc."lvm/lvm.conf".text = ''
          activation/thin_pool_autoextend_threshold = 80
          activation/thin_pool_autoextend_percent = 10
        '';

        my = {
          server.enable = true;

          # Root inside this VM belongs to the agents, so it gets no shared secrets: in particular
          # not `user-passwd.txt`
          user = {
            passwordSecret = null;
            config = {
              password = null;
              hashedPassword = "!";
            };
          };

          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBCkgBZh/YejY+gDnGa9r5SPo1+aHWPAAAIfENE7t0Om";
            files = {
              "slop-cannon/gitea-token".owner = agentUser;
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
            # Agents get root (passwordless `doas`) and can run nested VMs
            extraGroups = [ "wheel" "kvm" ];
            hashedPassword = "!";
            shell = pkgs.fish;
            openssh.authorizedKeys.keyFiles = [ lib.my.c.sshKeyFiles.me ];
          };
        };

        home-manager.users.${agentUser} = {
          my.agents = {
            enable = true;
            slop.enable = true;
            rules.gitea = giteaRule;
          };

          home.packages = [ slopClone slopPair tea ];

          programs = {
            # Permissive by default: the VM is the boundary, and `slop-broker` gates what needs
            # credentials
            claude-code.settings.permissions = {
              defaultMode = "bypassPermissions";
              allow = claudeAllow;
              deny = claudeDeny;
            };
            codex.settings = {
              cli_auth_credentials_store = "file";
              approval_policy = "never";
              sandbox_mode = "danger-full-access";
            };

            git.settings.credential.${giteaUrl}.helper = "${gitCredential}";
          };
        };

        # Not editable by the agent user without `doas`; a convenience, not a boundary
        environment.etc."claude-code/managed-settings.json".text = toJSON {
          permissions.deny = claudeDeny;
        };

        systemd = {
          network = {
            links = {
              "10-lan-untrusted" = {
                matchConfig = {
                  Driver = "mlx5_core";
                  PermanentMACAddress = "52:54:00:71:22:ea";
                };
                linkConfig = {
                  Name = "lan-untrusted";
                  MTUBytes = toString prefixes.untrusted.mtu;
                };
              };
            };
            networks = {
              "80-lan-untrusted" = mkMerge [
                (networkdAssignment "lan-untrusted" assignments.untrusted)
                {
                  # As `untrusted`'s DHCP and RAs hand out; the routers' resolvers aren't reachable
                  networkConfig.DNS = [
                    "1.1.1.1" "1.0.0.1"
                    "2606:4700:4700::1111" "2606:4700:4700::1001"
                  ];
                }
              ];
            };
          };

          services = {
            paseo = {
              unitConfig.RequiresMountsFor = agentHome;
              serviceConfig.EnvironmentFile = paseoPasswordFile;
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
            app.baseUrl = "https://slop.${lib.my.c.pubDomain}";
            daemon = {
              # Keep agents from changing modes, answering prompts or opening terminals
              mcp.injectIntoAgents = false;
              relay.requireProtectedSecurity = true;
              # Paseo can't change a provider's default mode, only offer these; `slop-broker` gates
              # what needs credentials
              agentProfiles = [
                {
                  id = "claude-bypass";
                  name = "Claude, bypass permissions";
                  provider = "claude";
                  modeId = "bypassPermissions";
                }
                {
                  id = "codex-full-access";
                  name = "Codex, full access";
                  provider = "codex";
                  modeId = "full-access";
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
