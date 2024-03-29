{ lib, pkgs, config, systems, ... }:
let
  inherit (builtins) head attrNames;
  inherit (lib) mkMerge mkIf mkDefault optionalAttrs mapAttrs' optionalString;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.deploy;

  keepGensOpt = with lib.types; mkOpt' ints.unsigned 10
    "Number of generations to keep when cleaning up old deployments (0 to disable deletion on deployment).";
  keepGensSnippet = p: n: optionalString (n > 0) ''
    ${config.nix.package}/bin/nix-env -p "${p}" --delete-generations +${toString n}
  '';

  # Based on https://github.com/serokell/deploy-rs/blob/master/flake.nix
  nixosActivate = cfg': base: (pkgs.deploy-rs.lib.activate.custom // {
    dryActivate = "$PROFILE/bin/switch-to-configuration dry-activate";
    boot = ''
      $PROFILE/bin/switch-to-configuration boot

      ${keepGensSnippet "$PROFILE" cfg'.keepGenerations}
    '';
  }) base.config.system.build.toplevel ''
    # work around https://github.com/NixOS/nixpkgs/issues/73404
    cd /tmp

    "$PROFILE"/bin/switch-to-configuration switch

    # https://github.com/serokell/deploy-rs/issues/31
    ${with base.config.boot.loader;
    optionalString systemd-boot.enable
    "sed -i '/^default /d' ${efi.efiSysMountPoint}/loader/loader.conf"}

    ${keepGensSnippet "$PROFILE" cfg'.keepGenerations}
  '';

  systemdUtil = pkgs.writeShellApplication {
    name = "systemd-util.sh";
    text = ''
      svcActionWatch() {
        action="$1"
        shift
        unit="$1"
        shift

        journalctl -o cat --no-pager -n 0 -f -u "$unit" &
        jPid=$!
        cleanup() {
          # shellcheck disable=SC2317
          kill "$jPid"
        }
        trap cleanup EXIT

        systemctl "$@" "$action" "$unit"
      }
    '';
  };

  ctrProfiles = optionalAttrs cfg.generate.containers.enable (mapAttrs' (n: c:
  let
    ctrConfig = systems."${n}".configuration.config;
  in
  {
    name = "container-${n}";
    value = {
      path = (pkgs.deploy-rs.lib.activate.custom // {
        boot = ''
          echo "Next systemd-nspawn@${n}.service restart / reload will load config"
        '';
      }) ctrConfig.my.buildAs.container ''
        source ${systemdUtil}/bin/systemd-util.sh
        ${if c.hotReload then ''
          if (! systemctl show -p ActiveState systemd-nspawn@${n} | grep -q "ActiveState=active") || \
            systemctl show -p StatusText systemd-nspawn@${n} | grep -q "Dummy container"; then
            action=restart
          else
            action=reload
          fi

          svcActionWatch "$action" systemd-nspawn@${n}
        '' else ''
          svcActionWatch restart systemd-nspawn@${n}
        ''}

        ${keepGensSnippet "$PROFILE" cfg.generate.containers.keepGenerations}
      '';
      profilePath = "/nix/var/nix/profiles/per-container/${n}/system";

      user = "root";
    };
  }) config.my.containers.instances);
in
{
  options.my.deploy = with lib.types; {
    authorizedKeys = {
      keys = mkOpt' (listOf singleLineStr) [ ] "SSH public keys to add to the default deployment user.";
      keyFiles = mkOpt' (listOf path) [ lib.my.c.sshKeyFiles.deploy ] "SSH public key files to add to the default deployment user.";
    };

    enable = mkBoolOpt' true "Whether to expose deploy-rs configuration for this system.";
    inherit (lib.my.deploy-rs) node;

    generate = {
      system = {
        enable = mkBoolOpt' true "Whether to generate a deploy-rs profile for this system's config.";
        mode = mkOpt' str "switch" "switch-to-configuration mode.";
        keepGenerations = keepGensOpt;
      };
      containers = {
        enable = mkBoolOpt' true "Whether to generate deploy-rs profiles for this system's containers.";
        keepGenerations = keepGensOpt;
      };
    };
  };

  config = mkMerge [
    {
      my.deploy.enable = mkIf (config.my.build.isDevVM || config.boot.isContainer) false;
    }
    (mkIf cfg.enable {
      my.deploy.node = {
        hostname = mkDefault config.networking.fqdn;
        profilesOrder = [ "system" ] ++ (attrNames ctrProfiles);
        profiles = {
          system = mkIf cfg.generate.system.enable {
            path = nixosActivate cfg.generate.system { inherit config; };

            user = "root";
          };
        } // ctrProfiles;

        sshUser = "deploy";
        user = mkDefault "root";
        sudo = mkDefault (if config.security.doas.enable then "doas -u" else "sudo -u");
        sshOpts = mkDefault [ "-p" (toString (head config.services.openssh.ports)) ];
      };

      users = {
        users."${cfg.node.sshUser}" = {
          isSystemUser = true;
          group = cfg.node.sshUser;
          extraGroups = mkDefault [ "wheel" ];
          shell = pkgs.bash;
          openssh.authorizedKeys = cfg.authorizedKeys;
        };
        groups."${cfg.node.sshUser}" = {};
      };
    })
  ];
}
