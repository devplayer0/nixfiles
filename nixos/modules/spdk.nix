{ lib, pkgs, config, ... }:
let
  inherit (builtins) toJSON;
  inherit (lib) optional optionalAttrs mapAttrsToList mkIf withFeature;
  inherit (lib.my) mkOpt' mkBoolOpt';

  rpcOpts = with lib.types; {
    options = {
      method = mkOpt' str null "RPC method name.";
      params = mkOpt' (attrsOf unspecified) { } "RPC params";
    };
  };

  cfg = config.my.spdk;
  config' = {
    subsystems = mapAttrsToList (subsystem: c: {
      inherit subsystem;
      config = map (rpc: {
        inherit (rpc) method;
      } // (optionalAttrs (rpc.params != { }) { inherit (rpc) params; })) c;
    }) cfg.config.subsystems;
  };
  configJSON = pkgs.writeText "spdk-config.json" (toJSON config');

  spdk = pkgs.spdk.overrideAttrs (o: {
    configureFlags = o.configureFlags ++ (map (withFeature true) [ "rdma" "ublk" ]);
    buildInputs = o.buildInputs ++ (with pkgs; [ liburing ]);
    # SPDK 26.01 recognizes prerelease DPDK 26.03, but selects the old PCI ABI for its release.
    # TODO: Remove after upgrading to SPDK >= 26.05, which handles released DPDK 26.03:
    # https://github.com/spdk/spdk/blob/v26.05/lib/env_dpdk/pci_dpdk.c
    # nixos-unstable still packages 26.01 without this fix (checked 2026-11-15).
    postPatch = (o.postPatch or "") + lib.optionalString (o.version == "26.01") ''
      substituteInPlace lib/env_dpdk/pci_dpdk.c \
        --replace-fail 'else if (year == 25) {' \
          'else if (year == 25 || (year == 26 && month == 3 && minor == 0)) {'
    '';
  });
  spdk-rpc = (pkgs.writeShellScriptBin "spdk-rpc" ''
    exec ${pkgs.python3}/bin/python3 ${spdk.src}/scripts/rpc.py "$@"
  '');
  spdk-setup = (pkgs.writeShellScriptBin "spdk-setup" ''
    exec ${spdk.src}/scripts/setup.sh "$@"
  '');
  spdk-debug = pkgs.writeShellApplication {
    name = "spdk-debug";
    runtimeInputs = [ spdk ];
    text = ''
      set -m
      if [ "$(id -u)" -ne 0 ]; then
        echo "I need to be root!"
        exit 1
      fi

      spdk_tgt ${cfg.extraArgs} --wait-for-rpc &
      until spdk-rpc spdk_get_version > /dev/null; do
        sleep 0.5
      done

      spdk-rpc bdev_set_options --disable-auto-examine
      spdk-rpc framework_start_init

      ${cfg.debugCommands}

      fg %1
    '';
  };
in
{
  options.my.spdk = with lib.types; {
    enable = mkBoolOpt' false "Whether to enable SPDK target.";
    extraArgs = mkOpt' str "" "Extra arguments to pass to spdk_tgt.";
    debugCommands = mkOpt' lines "" "Commands to run with the spdk-debug script.";
    config.subsystems = mkOpt' (attrsOf (listOf (submodule rpcOpts))) { } "Subsystem config / RPCs.";
  };

  config = mkIf cfg.enable {
    boot.kernelModules = [ "ublk_drv" ];

    environment.systemPackages = [
      spdk
      spdk-setup
      spdk-rpc
    ] ++ (optional (cfg.debugCommands != "") spdk-debug);

    systemd.services = {
      spdk-tgt = {
        description = "SPDK target";
        path = with pkgs; [
          bash
          python3
          kmod
          gawk
          util-linux
        ];
        serviceConfig = {
          ExecStartPre = "${spdk.src}/scripts/setup.sh";
          ExecStart = "${spdk}/bin/spdk_tgt ${cfg.extraArgs} -c ${configJSON}";
        };
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
