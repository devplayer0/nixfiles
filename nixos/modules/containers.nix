{ lib, pkgs, options, config, systems, ... }:
let
  inherit (builtins) attrNames attrValues all hashString toJSON;
  inherit (lib)
    groupBy' mapAttrsToList optionalString optional concatMapStringsSep filterAttrs mkOption mkDefault mkIf mkMerge;
  inherit (lib.my) mkOpt' mkBoolOpt' attrsToNVList;

  cfg = config.my.containers;

  devVMKeyPath = "/run/dev.key";
  ctrProfiles = n: "/nix/var/nix/profiles/per-container/${n}";

  dummyProfile = pkgs.writeTextFile {
    name = "dummy-init";
    executable = true;
    destination = "/init";
    # Although this will be in the new root, the shell will be available because the store will be mounted!
    text = ''
      #!${pkgs.runtimeShell}
      ${pkgs.iproute2}/bin/ip link set dev host0 up

      while true; do
        echo "This is a dummy, please deploy the real container!"
        ${pkgs.coreutils}/bin/sleep 5
      done
    '';
  };

  bindMountOpts = with lib.types; { name, ... }: {
    options = {
      mountPoint = mkOption {
        example = "/mnt/usb";
        type = str;
        description = "Mount point on the container file system.";
      };
      hostPath = mkOption {
        default = null;
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

    config = {
      mountPoint = mkDefault name;
    };
  };

  netZoneOpts = with lib.types; { name, ... }: {
    options = {
      hostAddresses = mkOpt' (either str (listOf str)) null "Addresses for the host bridge.";
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
      networkZone = mkOpt' str "containers" "Network zone to connect to.";
    };
  };
in
{
  options.my.containers = with lib.types; {
    persistDir = mkOpt' str "/persist/containers" "Where to store container persistence data.";
    instances = mkOpt' (attrsOf (submodule containerOpts)) { } "Individual containers.";
    networkZones = mkOpt' (attrsOf (submodule netZoneOpts)) {
      "containers" = {
        hostAddresses = "172.16.137.1/24";
      };
    } "systemd-nspawn network zones";
  };

  config = mkMerge [
    (mkIf (cfg.instances != { }) {
      assertions = [
        {
          assertion = config.systemd.network.enable;
          message = "Containers currently require systemd-networkd!";
        }
        {
          assertion = all (z: cfg.networkZones ? "${z}") (mapAttrsToList (_: c: c.networkZone) cfg.instances);
          message = "Each container must be within one of the configured network zones.";
        }
      ];

      my.firewall.trustedInterfaces = (attrNames cfg.networkZones) ++ (map (n: "vb-${n}") (attrNames cfg.instances));

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
      ] ++ (mapAttrsToList (n: z: {
        network = {
          netdevs."25-container-bridge-${n}".netdevConfig = {
            Name = n;
            Kind = "bridge";
          };
          # Replace the pre-installed config
          networks."80-container-bridge-${n}" = {
            matchConfig = {
              Name = n;
              Driver = "bridge";
            };
            networkConfig = {
              Address = z.hostAddresses;
              DHCPServer = true;
              # TODO: Configuration for routed IPv6 (and maybe IPv4)
              IPMasquerade = "both";
              IPv6SendRA = true;
            };
          };
        };
      }) cfg.networkZones) ++ (mapAttrsToList (n: c: {
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
          networkConfig = {
            Bridge = c.networkZone;
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
          # systemd.nspawn units can't set the root directory directly, but /run/machines/${n} is one of the search paths
          environment.root = "/run/machines/${n}";
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
                ${pkgs.nix}/bin/nix-env -p ${sysProfile} --set ${dummyProfile}
              fi
            ''}

            mkdir -p -m 0755 "$root"/sbin "$root"/etc
            touch "$root"/etc/os-release
            ln -sf "${containerSystem}"/init "$root"/sbin/init
          '';
          postStop =
          ''
            rm -rf "$root"
          '';
          reload =
          ''
            [ -e "${system}"/bin/switch-to-configuration ] && \
              systemd-run --pipe --machine ${n} -- "${containerSystem}"/bin/switch-to-configuration test
          '';

          wantedBy = optional c.autoStart "machines.target";
        };
        network.networks."80-container-${n}-vb" = {
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
            Bridge = c.networkZone;
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

      my = {
        tmproot.enable = true;
      };

      system.activationScripts = {
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
          DHCP = "yes";
          LLDP = true;
          EmitLLDP = "customer-bridge";
        };
        dhcpConfig = {
          UseTimezone = true;
        };
      };

      # If the host is a dev VM
      age.identityPaths = [ devVMKeyPath ];
    })
  ];
}
