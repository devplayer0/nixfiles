{ lib, pkgs, config, self, ... }:
let
  inherit (builtins) any head attrValues attrNames isAttrs isList length concatLists;
  inherit (lib) mkIf mkMerge mapAttrs mapAttrsToList filterAttrs optional optionals hasPrefix unique concatStringsSep;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.slop-broker;
  ha = cfg.homeAssistant;

  isRuntimePath = p: hasPrefix "/" p && !(hasPrefix "/nix/store/" p);
  hasLocalRequesters = any (r: r.uid != null) (attrValues cfg.requesters);
  hasVsockRequesters = any (r: r.vsockCid != null) (attrValues cfg.requesters);
  missingPolicies = attrNames (filterAttrs (_: r: !(cfg.policies ? ${r.policy})) cfg.requesters);

  # Each SSH key gets a forced command naming its owner and role
  remoteUser = "slop";
  remoteKeys = concatLists (
    mapAttrsToList (n: r: map (key: { inherit key; role = "requester"; name = n; }) r.sshKeys) cfg.requesters
    ++ mapAttrsToList (n: keys: map (key: { inherit key; role = "approver"; name = n; }) keys) cfg.sshApprovers
  );
  hasRemote = remoteKeys != [ ];
  authorizedKey = k: ''restrict,command="${cfg.package}/bin/slop-broker remote ${k.role} ${k.name}" ${k.key}'';

  # TOML has no null; leave those keys out
  dropNulls = v:
    if isAttrs v then mapAttrs (_: dropNulls) (filterAttrs (_: x: x != null) v)
    else if isList v then map dropNulls v
    else v;

  duration = lib.types.strMatching "[1-9][0-9]*[smhd]";

  opOpts = with lib.types; {
    options = {
      action = mkOpt' (enum [ "auto" "ask" "deny" ]) "ask" "What happens to a request.";
      leases = mkOpt' (listOf duration) [ ] "Lease lengths approvers are offered, like `5m` or `1h`.";
      rules = mkOpt' (listOf (submodule {
        options = {
          match = mkOpt' (attrsOf str) { } "Scope fields and the globs they must match.";
          action = mkOpt' (enum [ "auto" "ask" "deny" ]) null "Action for matching requests.";
          leases = mkOpt' (nullOr (listOf duration)) null "Leases for matching requests (null keeps the default).";
        };
      })) [ ] "Rules checked in order; the first match wins.";
    };
  };

  policyOpts = with lib.types; {
    options = {
      maxPending = mkOpt' ints.positive 4 "Requests that may wait for approval at once, for each requester.";
      autoPerMinute = mkOpt' ints.positive 60 "Requests per minute that policy approves by itself, for each requester.";
      ops = mkOpt' (attrsOf (submodule opOpts)) { } "Policy per operation; unlisted operations are denied.";
    };
  };

  requesterOpts = with lib.types; {
    options = {
      vsockCid = mkOpt' (nullOr ints.unsigned) null "CID of a VM that connects over vsock.";
      uid = mkOpt' (nullOr ints.unsigned) null "UID of a local requester.";
      sshKeys = mkOpt' (listOf str) [ ] "SSH public keys a requester on another box connects with (as `${remoteUser}`).";
      policy = mkOpt' str null "Name of the requester's policy in `policies`.";
    };
  };

  brokerConfig = (pkgs.formats.toml { }).generate "slop-broker.toml" (dropNulls {
    requesters = mapAttrs (_: r: {
      vsock_cid = r.vsockCid;
      inherit (r) uid policy;
      remote = r.sshKeys != [ ];
    }) cfg.requesters;

    policies = mapAttrs (_: p: {
      max_pending = p.maxPending;
      auto_per_minute = p.autoPerMinute;
      inherit (p) ops;
    }) cfg.policies;

    inherit (cfg) timeout;
    vsock_port = if hasVsockRequesters then cfg.vsockPort else null;
    request_socket = if hasLocalRequesters then "/run/slop-broker/request.sock" else null;
    approve_socket = "/run/slop-broker/approve.sock";
    approver_group = "slop-broker-approve";
    audit_log = "/var/lib/slop-broker/audit.jsonl";

    ssh = if cfg.ssh.enable then {
      ssh = "${pkgs.openssh}/bin/ssh";
      key = "ssh-key";
      known_hosts = "/var/lib/slop-broker/known_hosts";
      targets = mapAttrs (_: t: { inherit (t) hostname user sudo; ssh_opts = t.sshOpts; }) cfg.ssh.targets;
    } else null;

    deploy = if cfg.deploy.enable then {
      builder = with cfg.deploy.builder; { inherit hostname user; ssh_opts = sshOpts; };
      nix = "${config.nix.package}/bin/nix";
      cache = "/var/lib/slop-broker/cache";
    } else null;

    remote = if hasRemote then {
      socket = "/run/slop-broker/remote.sock";
      user = remoteUser;
      approvers = attrNames cfg.sshApprovers;
    } else null;

    home_assistant = if ha.enable then {
      inherit (ha) url;
      notify_service = ha.notifyService;
      device_id = ha.deviceId;
      token = "ha-token";
    } else null;
  });
in
{
  options.my.slop-broker = with lib.types; {
    enable = mkBoolOpt' false "Whether to run the approval broker for coding agents.";
    package = mkOpt' package pkgs.slop-broker "slop-broker package.";

    vsockPort = mkOpt' ints.unsigned 6262 "vsock port to listen on for VM requesters.";
    timeout = mkOpt' duration "5m" "How long a request waits for an approver.";
    approvers = mkOpt' (listOf str) [ ] "Local users allowed to answer requests with `slop-approve`.";
    sshApprovers = mkOpt' (attrsOf (listOf str)) { }
      "Approvers on other boxes, by name, with the SSH public keys `slop-approve` connects with.";
    policies = mkOpt' (attrsOf (submodule policyOpts)) { } "Named policies; several requesters can share one.";
    requesters = mkOpt' (attrsOf (submodule requesterOpts)) { } "Who may send requests, and which policy applies.";

    ssh = {
      enable = mkBoolOpt' false "Whether to run approved SSH commands.";
      keyFile = mkOpt' str "" "Runtime path to the SSH private key; never a Nix store path.";
      targets = mkOpt' (attrsOf (submodule {
        options = {
          hostname = mkOpt' str null "Host to connect to.";
          user = mkOpt' str null "Remote user.";
          sshOpts = mkOpt' (listOf str) [ ] "Extra SSH arguments (trusted).";
          sudo = mkOpt' str "doas -u" "How the user becomes root for deploys, followed by `root`.";
        };
      })) (mapAttrs (_: n: { inherit (n) hostname sshOpts; user = n.sshUser; sudo = n.sudo or "doas -u"; }) self.deploy.nodes)
        "Named SSH targets; defaults to every deploy-rs node.";
    };

    deploy = {
      enable = mkBoolOpt' false "Whether to build and deploy commits (`slop deploy`); needs `ssh`.";
      builder = {
        hostname = mkOpt' str "localhost" "Box running the builder (`my.slop-broker-builder`).";
        user = mkOpt' str "slop-broker-build" "The builder's user.";
        sshOpts = mkOpt' (listOf str) [ "-p" (toString (head config.services.openssh.ports)) ]
          "Extra SSH arguments for reaching the builder.";
      };
    };

    homeAssistant = {
      enable = mkBoolOpt' false "Whether to send Companion approval notifications.";
      url = mkOpt' str "" "Home Assistant WebSocket endpoint, preferably wss://host/api/websocket.";
      notifyService = mkOpt' str "" "Companion notification service name, without the notify. prefix.";
      deviceId = mkOpt' str ""
        "The Companion app's own ID (the `device_id` in its notification answers, not the device registry's); the broker logs it when it ignores an answer.";
      tokenFile = mkOpt' str "" "Runtime path to a Home Assistant token; never a Nix store path.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.ssh.enable -> isRuntimePath cfg.ssh.keyFile;
        message = "slop-broker SSH needs a runtime key file.";
      }
      {
        assertion = cfg.deploy.enable -> cfg.ssh.enable;
        message = "slop-broker deploys need `ssh`.";
      }
      {
        assertion = missingPolicies == [ ];
        message = "slop-broker requesters with an unknown policy: ${concatStringsSep ", " missingPolicies}.";
      }
      {
        assertion = length (unique (map (k: k.key) remoteKeys)) == length remoteKeys;
        message = "slop-broker SSH keys must be distinct; use separate keys for requesting and approving.";
      }
      {
        assertion = ha.enable -> (ha.url != "" && ha.notifyService != "" && ha.deviceId != "" && isRuntimePath ha.tokenFile);
        message = "slop-broker Home Assistant needs a URL, service, device ID and runtime token file.";
      }
    ];

    users = mkMerge [
      {
        groups = {
          slop-broker = { };
          slop-broker-approve.members = cfg.approvers;
        };
        users.slop-broker = {
          isSystemUser = true;
          group = "slop-broker";
        };
      }
      # Remote requesters and approvers log in as this user; their keys only run `slop-broker remote`
      (mkIf hasRemote {
        groups.${remoteUser} = { };
        users.${remoteUser} = {
          isSystemUser = true;
          group = remoteUser;
          shell = pkgs.bashInteractive;
          openssh.authorizedKeys.keys = map authorizedKey remoteKeys;
        };
      })
    ];

    environment.systemPackages = [ cfg.package ];
    boot.kernelModules = optional hasVsockRequesters "vhost_vsock";
    my.tmproot.persistence.config.directories = [
      {
        directory = "/var/lib/slop-broker";
        user = "slop-broker";
        group = "slop-broker";
        mode = "0700";
      }
    ];

    systemd.services.slop-broker = {
      description = "Approval broker for coding agents";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/slop-broker serve --config ${brokerConfig}";
        LoadCredential =
          optional cfg.ssh.enable "ssh-key:${cfg.ssh.keyFile}" ++
          optional ha.enable "ha-token:${ha.tokenFile}";

        User = "slop-broker";
        Group = "slop-broker";
        SupplementaryGroups = [ "slop-broker-approve" ] ++ optional hasRemote remoteUser;
        RuntimeDirectory = "slop-broker";
        RuntimeDirectoryMode = "0755";
        StateDirectory = "slop-broker";
        StateDirectoryMode = "0700";
        Restart = "on-failure";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictAddressFamilies = [ "AF_UNIX" ]
          ++ optional hasVsockRequesters "AF_VSOCK"
          ++ optionals (cfg.ssh.enable || ha.enable) [ "AF_INET" "AF_INET6" ];
        CapabilityBoundingSet = "";
        UMask = "0077";
      };
    };
  };
}
