{
  nixos.systems.palace.configuration = { lib, config, allAssignments, ... }:
  let
    # `slop-cannon`'s vsock address; the kernel reports it for every connection from the guest
    slopCannonCid = 3;

    # Home's pair, and colony's
    routers = [ "river" "stream" "estuary" ];

    middleman = allAssignments.middleman.internal;
    webPort = config.services.slop-broker.web.port;
  in
  {
    my = {
      secrets.files = {
        "palace/slop-broker-deploy.key" = {
          owner = "root";
          mode = "0400";
        };
        # Pushes `slop build` outputs into Harmonia's store on `object`
        "palace/slop-broker-cache.key" = {
          owner = "root";
          mode = "0400";
        };
        # The approvals web app's client secret at Pocket ID
        "palace/slop-broker-oidc-secret" = {
          owner = "root";
          mode = "0400";
        };
        # Read-only deploy key for `dev/nixfiles` on Gitea
        "palace/slop-broker-git.key" = {
          owner = "slop-broker-build";
          group = "slop-broker-build";
          mode = "0400";
        };
      };

      vms.instances.slop-cannon.qemuFlags = [ "device vhost-vsock-pci,guest-cid=${toString slopCannonCid}" ];

      # Builds and the builder run agent-written Nix, so like `lan-untrusted` they only get the
      # Internet (and `resolved`'s stub, which builds use for DNS)
      firewall.extraRules = ''
        table inet filter {
          chain agent-builds {
            ct state established,related return
            ip daddr 127.0.0.53 meta l4proto { tcp, udp } th dport 53 return
            ${lib.my.c.internalNets.nftReject}
          }
          chain output {
            meta skgid ${toString config.ids.gids.nixbld} jump agent-builds
            meta skuid slop-broker-build jump agent-builds
          }
          # Only `middleman`, which publishes it, may reach the web app; `input` (not `wan-tcp`, which
          # ends in `return`) gets these after everything else
          chain input {
            ip saddr ${middleman.ipv4.address} tcp dport ${toString webPort} accept
            ip6 saddr ${middleman.ipv6.address} tcp dport ${toString webPort} accept
          }
        }
      '';
    };

    # Builds commits for `slop deploy` and `slop build`, as a user without keys; reached over SSH
    # like a separate box
    services.slop-broker-builder = {
      enable = true;
      repository = "git@git.nul.ie:dev/nixfiles.git";
      keyFile = config.age.secrets."palace/slop-broker-git.key".path;
      brokerKeys = [ (lib.trim (builtins.readFile lib.my.c.sshKeyFiles.deploy)) ];
    };

    services.slop-broker = {
      enable = true;
      approvers = [ config.my.user.config.name ];

      # For coding agents, wherever they run
      policies.agent.ops = {
        # Fixed read-only commands built by the broker
        query.action = "auto";
        # Running agent-written Nix at all; approvers see the commits and diff. Commits already
        # on `master` have been reviewed.
        builder = {
          action = "ask";
          leases = [ "1h" ];
          rules = [
            {
              match.on_branch = "true";
              action = "auto";
            }
          ];
        };
        deploy = {
          action = "ask";
          # The routers carry everything else; a bad deploy there is hard to reach and undo
          rules = map
            (node: {
              match.node = node;
              action = "ask";
              confirm = "passkey";
            })
            routers;
        };
        # The source was reviewed for `builder`, and the cache only gets what `palace` built
        build.action = "auto";
        ssh = {
          action = "ask";
          leases = [ "5m" "1h" ];
        };
      };

      requesters.slop-cannon = {
        vsockCid = slopCannonCid;
        policy = "agent";
      };

      # Agents on `castle` connecting over SSH
      requesters.castle = {
        sshKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINY4Znri43VCA0gJYBbO9g72OsN3xnMYbMZ79G5tAZnr slop requester (castle)"
        ];
        policy = "agent";
      };

      # Answering requests from `castle` over SSH
      sshApprovers.castle = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAnv2y4uuABxHtk2iXhKe67W8jRIJcLrDVt9/LQaG14l slop approver (castle)" ];

      ssh = {
        enable = true;
        keyFile = config.age.secrets."palace/slop-broker-deploy.key".path;
      };
      deploy.enable = true;
      cache = {
        enable = true;
        hostname = "object-ctr.${lib.my.c.colony.domain}";
        user = "harmonia";
        keyFile = config.age.secrets."palace/slop-broker-cache.key".path;
      };

      # `approve.slop.nul.ie`, published by `middleman`; approvers sign in with Pocket ID
      web = {
        enable = true;
        address = "::";
        url = "https://approve.slop.${lib.my.c.pubDomain}";
        issuer = "https://id.${lib.my.c.pubDomain}";
        clientSecretFile = config.age.secrets."palace/slop-broker-oidc-secret".path;
      };
    };

    # The ruleset check runs where `slop-broker-build` doesn't exist
    networking.nftables.preCheckRuleset = ''
      sed 's/skuid slop-broker-build/skuid nobody/g' -i ruleset.conf
    '';

    # Builds share the host with the VMs, including the router; keep them from starving those
    systemd.services.nix-daemon.serviceConfig = {
      MemoryHigh = "32G";
      MemoryMax = "40G";
      CPUWeight = 20;
    };
  };
}
