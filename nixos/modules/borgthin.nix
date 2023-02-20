{ lib, pkgs, config, ... }:
let
  inherit (builtins) substring match;
  inherit (lib)
    nameValuePair optional optionalString optionalAttrs mapAttrs' mapAttrsToList concatStringsSep
    concatMapStringsSep mkIf;
  inherit (lib.my) mkOpt' mkBoolOpt';

  jobType = with lib.types; submodule ({ name, ... }@args:
  let
    cfg = args.config;
  in
  {
    options = {
      repo = mkOpt' str null "borg repository URL";
      passFile = mkOpt' (nullOr str) null "Path to file containing passphrase";

      archivePrefix = mkOpt' str "${config.networking.hostName}-${name}-" "Prefix to start new archives with";
      dateFormat = mkOpt' str "+%Y-%m-%dT%H:%M:%S" "Format passed to the date command";
      compression = mkOpt' str "zstd,3" "Compression options";
      lvs = mkOpt' (listOf str) null "Thin LVs to backup (vg/lv format)";
      prune = {
        pattern = mkOpt' str "sh:${cfg.archivePrefix}*" "Borg pattern to select archives for pruning";
        keep = mkOpt' (attrsOf (either int str)) { } "Borg pruning params";
      };

      extraArgs = mkOpt' (listOf str) [ "--iec" ] "Extra args to pass to all borg commands";
      extraCreateArgs = mkOpt' (listOf str) [ ] "Extra args to pass to tcreate command";
      environment = mkOpt' (attrsOf str) { } "Extra environment variables to pass to borg";

      timer = {
        at = mkOpt' (either str (listOf str)) "5:00" "systemd calendar time(s) to run backup at";
        persistent = mkBoolOpt' false "Persistent systemd timer";
      };
    };
  });

  cfg' = config.my.borgthin;

  isLocalPath = x:
    substring 0 1 x == "/"      # absolute path
    || substring 0 1 x == "."   # relative path
    || match "[.*:.*]" == null; # not machine:path

  argStr = concatMapStringsSep " " (a: ''"${a}"'');

  mkEnv = name: cfg: (rec {
    BORG_BASE_DIR = "/var/lib/borgthin";
    BORG_CONFIG_DIR = "${BORG_BASE_DIR}/config";
    BORG_CACHE_DIR = "/var/cache/borgthin";

    BORG_REPO = cfg.repo;
  }) //
  (optionalAttrs (cfg.passFile != null) {
    BORG_PASSCOMMAND = "cat ${cfg.passFile}";
  }) //
  cfg.environment;

  # utility function around makeWrapper
  mkWrapperDrv = {
    original, name,
    set ? { }, addFlags ? [ ],
  }:
  pkgs.runCommand "${name}-wrapper" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    makeWrapper "${original}" "$out/bin/${name}" \
      ${concatStringsSep " \\\n " (
        (mapAttrsToList (name: value: ''--set ${name} "${value}"'') set) ++
        (map (f: ''--add-flags "${f}"'') addFlags)
      )}
  '';
  mkBorgWrapper = name: cfg: mkWrapperDrv {
    original = "${cfg'.package}/bin/borgthin";
    name = "borgthin-job-${name}";
    set = mkEnv name cfg;
    addFlags = cfg.extraArgs;
  };

  mkKeepArgs = keep:
    # If cfg.prune.keep e.g. has a yearly attribute,
    # its content is passed on as --keep-yearly
    concatStringsSep " "
      (mapAttrsToList (x: y: "--keep-${x}=${toString y}") keep);

  mkService = name: cfg: nameValuePair "borgthin-job-${name}" {
    description = "borgthin backup job ${name}";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "borgthin";
      CacheDirectory = "borgthin";

      # Only run when no other process is using CPU or disk
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
    };
    environment = mkEnv name cfg;

    path = [ cfg'.lvmPackage cfg'.thinToolsPackage cfg'.package ];
    script = ''
      extraArgs="${argStr cfg.extraArgs}"
      borgthin $extraArgs tcreate \
        --compression "${cfg.compression}" \
        ${argStr cfg.extraCreateArgs} \
        "${cfg.archivePrefix}$(date "${cfg.dateFormat}")" \
        ${concatStringsSep " " cfg.lvs}
    '' + optionalString (cfg.prune.keep != { }) ''
      borgthin $extraArgs prune \
        --match-archives "${cfg.prune.pattern}" \
        ${mkKeepArgs cfg.prune.keep}
      borgthin $extraArgs compact
    '';
  };

  mkTimer = name: cfg: nameValuePair "borgthin-job-${name}" {
    description = "borgthin backup job ${name} timer";
    after = optional (cfg.timer.persistent && !isLocalPath cfg.repo) "network-online.target";
    timerConfig = {
      Persistent = cfg.timer.persistent;
      OnCalendar = cfg.timer.at;
    };
    wantedBy = [ "timers.target" ];
  };
in
{
  options.my.borgthin = with lib.types; {
    enable = mkBoolOpt' false "Whether to enable borgthin jobs";
    lvmPackage = mkOpt' package pkgs.lvm2 "Packge containing LVM tools";
    thinToolsPackage = mkOpt' package pkgs.thin-provisioning-tools "Package containing thin-provisioning-tools";
    package = mkOpt' package pkgs.borgthin "borgthin package";
    jobs = mkOpt' (attrsOf jobType) { } "borgthin jobs";
  };

  config = mkIf cfg'.enable {
    environment.systemPackages =
      [ cfg'.package ] ++
      (mapAttrsToList mkBorgWrapper cfg'.jobs);

    systemd = {
      services = mapAttrs' mkService cfg'.jobs;
      timers = mapAttrs' mkTimer cfg'.jobs;
    };

    my.tmproot.persistence.config.directories = [
      "/var/lib/borgthin"
      "/var/cache/borgthin"
    ];
  };
}

