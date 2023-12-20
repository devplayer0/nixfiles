{ lib, pkgs, options, config, systems, ... }:
let
  inherit (builtins) attrNames attrValues all hashString toJSON;
  inherit (lib)
    groupBy' mapAttrsToList optionalString optional concatMapStringsSep filterAttrs mkOption mkDefault mkIf mkMerge;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.containers;

  devVMKeyPath = "/run/dev.key";
  ctrProfiles = n: "/nix/var/nix/profiles/per-container/${n}";

  dummyReady = pkgs.runCommandCC "dummy-sd-ready" {
    buildInputs = [ pkgs.systemd ];
    passAsFile = [ "code" ];
    code = ''
      #include <stdio.h>
      #include <signal.h>
      #include <unistd.h>
      #include <systemd/sd-daemon.h>

      void handler(int signum) {
        exit(0);
      }

      int main() {
        // systemd sends this to PID 1 for an "orderly shutdown"
        signal(SIGRTMIN+3, handler);

        int ret =
          sd_notifyf(0, "READY=1\n"
            "STATUS=Dummy container, please deploy for real!\n"
            "MAINPID=%lu",
            (unsigned long)getpid());
        if (ret <= 0) {
          fprintf(stderr, "sd_notify() returned %d\n", ret);
          return ret == 0 ? -1 : ret;
        }

        pause();
        return 0;
      };
    '';
  } ''
    $CC -o "$out" -x c -lsystemd "$codePath"
  '';
  dummyProfile = pkgs.writeTextFile {
    name = "dummy-init";
    executable = true;
    destination = "/init";
    # Although this will be in the new root, the shell will be available because the store will be mounted!
    text = ''
      #!${pkgs.runtimeShell}
      ${pkgs.iproute2}/bin/ip link set dev host0 up

      exec ${dummyReady}
    '';
  };

  bindMountOpts = with lib.types; { name, ... }: {
    options = {
      mountPoint = mkOption {
        default = name;
        example = "/mnt/usb";
        type = str;
        description = "Mount point on the container file system.";
      };
      hostPath = mkOption {
        default = name;
        example = "/home/alice";
        type = nullOr str;
        description = "Location of the host path to be mounted.";
      };
      readOnly = mkOption {
        default = true;
        type = bool;
        description = "Determine whether the mounted path will be accessed in read-only mode.";
      };
    };
  };

  containerOpts = with lib.types; { name, ... }: {
    options = {
      system = mkOpt' path "${ctrProfiles name}/system" "Path to NixOS system configuration.";
      containerSystem = mkOpt' path "/nix/var/nix/profiles/system" "Path to NixOS system configuration from within container.";
      autoStart = mkBoolOpt' true "Whether to start the container automatically at boot.";
      hotReload = mkBoolOpt' true
        "Whether to apply new configuration by running `switch-to-configuration` instead of rebooting the container.";

      # Yoinked from nixos/modules/virtualisation/nixos-containers.nix
      bindMounts = mkOption {
        type = attrsOf (submodule bindMountOpts);
        default = { };
        description =
          ''
            An extra list of directories that is bound to the container.
          '';
      };
      networking = {
        bridge = mkOpt' (nullOr str) null "Network bridge to connect to.";
      };
    };
  };
in
{
  options.my.containers = with lib.types; {
    persistDir = mkOpt' str "/persist/containers" "Where to store container persistence data.";
    instances = mkOpt' (attrsOf (submodule containerOpts)) { } "Individual containers.";
  };

  config = mkMerge [
    (mkIf (cfg.instances != { }) {
      assertions = [
        {
          assertion = config.systemd.network.enable;
          message = "Containers currently require systemd-networkd!";
        }
      ];

      # TODO: Better security
      my.firewall.trustedInterfaces =
        mapAttrsToList
          (n: _: "ve-${n}")
          (filterAttrs (_: c: c.networking.bridge == null) cfg.instances);

      systemd = mkMerge ([
        {
          # By symlinking to the original systemd-nspawn@.service for every instance we force the unit generator to
          # create overrides instead of replacing the unit entirely
          packages = [
            (pkgs.linkFarm "systemd-nspawn-containers" (map (n: {
              name = "etc/systemd/system/systemd-nspawn@${n}.service";
              path = "${pkgs.systemd}/example/systemd/system/systemd-nspawn@.service";
            }) (attrNames cfg.instances)))
          ];
        }
      ] ++ (mapAttrsToList (n: c: {
        nspawn."${n}" = {
          execConfig = {
            Boot = true;
            Ephemeral = true;
            LinkJournal = false;
            NotifyReady = true;
            ResolvConf = "bind-stub";
            PrivateUsers = false;
          };
          filesConfig =
          let
            binds = groupBy'
              (l: b: l ++ [ (if b.hostPath != null then "${b.hostPath}:${b.mountPoint}" else b.mountPoint) ])
              [ ]
              (b: if b.readOnly then "ro" else "rw")
              (attrValues c.bindMounts);
          in {
            BindReadOnly = [
              "/nix/store"
              "/nix/var/nix/db"
              "/nix/var/nix/daemon-socket"
            ] ++ optional config.my.build.isDevVM "${config.my.secrets.vmKeyPath}:${devVMKeyPath}" ++ binds.ro or [ ];
            Bind = [
              "${ctrProfiles n}:/nix/var/nix/profiles"
              "/nix/var/nix/gcroots/per-container/${n}:/nix/var/nix/gcroots"
              "${cfg.persistDir}/${n}:/persist"
            ] ++ binds.rw or [ ];
          };
          networkConfig = if (c.networking.bridge != null) then {
            Bridge = c.networking.bridge;
          } else {
            VirtualEthernet = true;
          };
        };
        services."systemd-nspawn@${n}" =
        let
          sysProfile = "${ctrProfiles n}/system";
          system = if
            config.my.build.isDevVM then
            systems."${n}".configuration.config.my.buildAs.container else
            c.system;
          containerSystem = if
            config.my.build.isDevVM then
            system else
            c.containerSystem;
        in
        {
          environment = {
            # systemd.nspawn units can't set the root directory directly, but /run/machines/${n} is one of the search paths
            root = "/run/machines/${n}";
            # Without this, systemd-nspawn will do cgroupsv1
            SYSTEMD_NSPAWN_UNIFIED_HIERARCHY = "1";
          };
          restartTriggers = [
            (''${n}.nspawn:${hashString "sha256" (toJSON config.systemd.nspawn."${n}")}'')
          ];

          preStart =
          ''
            mkdir -p -m 0755 \
              /nix/var/nix/{profiles,gcroots}/per-container/${n} \
              ${cfg.persistDir}/${n}

            ${optionalString (system == sysProfile)
            ''
              if [ ! -e "${sysProfile}" ]; then
                echo "Creating dummy profile"
                ${config.nix.package}/bin/nix-env -p ${sysProfile} --set ${dummyProfile}
              fi
            ''}

            mkdir -p -m 0755 "$root"/sbin "$root"/etc
            touch "$root"/etc/os-release

            ${if system == sysProfile then ''
              if [ -e "${sysProfile}"/prepare-root ]; then
                initSource="${containerSystem}"/prepare-root
              else
                initSource="${containerSystem}"/init
              fi
              ln -sf "$initSource" "$root"/sbin/init
            '' else ''
              ln -sf "${containerSystem}/prepare-root" "$root"/sbin/init
            ''}
          '';
          postStop =
          ''
            rm -rf "$root"
          '';
          reload =
          # `switch-to-configuration test` switches config without trying to update bootloader
          ''
            [ -e "${system}"/bin/switch-to-configuration ] && \
              systemd-run --pipe --machine ${n} -- "${containerSystem}"/bin/switch-to-configuration test
          '';

          wantedBy = optional c.autoStart "machines.target";
        };
        network.networks."80-container-${n}-vb" = mkIf (c.networking.bridge != null) {
          matchConfig = {
            Name = "vb-${n}";
            Driver = "veth";
          };
          networkConfig = {
            # systemd LLDP doesn't work on bridge interfaces
            LLDP = true;
            EmitLLDP = "customer-bridge";
            # Although nspawn will set the veth's master, systemd will clear it (systemd 250 adds a `KeepMaster`
            # to avoid this)
            Bridge = c.networking.bridge;
          };
        };
      }) cfg.instances));
    })

    # Inside container
    (mkIf config.boot.isContainer {
      assertions = [
        {
          assertion = config.systemd.network.enable;
          message = "Containers currently require systemd-networkd!";
        }
      ];

      nix = {
        gc.automatic = false;
      };

      my = {
        tmproot = {
          enable = true;
          persistence.dir = "/persist";
        };
      };

      system.activationScripts = {
        # So that update-users-groups.pl can see the saved info. Normally stage-1-init.sh would do these mounts early.
        earlyPersist.text = ''
          if ! mountpoint -q /var/lib/nixos; then
            mkdir -p {/persist,}/var/lib/nixos
            mount --bind {/persist,}/var/lib/nixos
          fi
        '';
        users.deps = [ "earlyPersist" ];

        # Ordinarily I think the Nix daemon does this but ofc it doesn't in the container
        createNixPerUserDirs = {
          text =
            let
              users = attrValues (filterAttrs (_: u: u.isNormalUser) config.users.users);
            in
              concatMapStringsSep "\n"
                (u: ''install -d -o ${u.name} -g ${u.group} /nix/var/nix/{profiles,gcroots}/per-user/"${u.name}"'') users;
          deps = [ "users" "groups" ];
        };

        # age requires all keys to at least exist, even if they're not going to be used
        agenixInstall.deps = [ "ensureDevKey" ];
        ensureDevKey.text =
        ''
          [ ! -e "${devVMKeyPath}" ] && touch "${devVMKeyPath}"
        '';
      };

      networking = {
        useHostResolvConf = false;
      };
      # Replace the pre-installed 80-container-host0
      systemd.network.networks."80-container-host0" = {
        matchConfig = {
          Name = "host0";
          Virtualization = "container";
        };
        networkConfig = {
          LLDP = true;
          EmitLLDP = "customer-bridge";
        };
      };

      # If the host is a dev VM
      age.identityPaths = [ devVMKeyPath ];
    })
  ];
}
