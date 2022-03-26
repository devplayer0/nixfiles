{ lib, options, config, systems, ... }:
let
  inherit (builtins) attrNames attrValues mapAttrs;
  inherit (lib) concatMapStringsSep filterAttrs mkDefault mkIf mkMerge mkAliasDefinitions mkVMOverride mkAfter;
  inherit (lib.my) mkOpt';

  cfg = config.my.containers;

  devVMKeyPath = "/run/dev.key";

  containerOpts = with lib.types; { name, ... }: {
    options = {
      system = mkOpt' unspecified systems."${name}".configuration.config.my.buildAs.container
        "Top-level system configuration.";
      opts = mkOpt' lib.my.naiveModule { } "Options to pass to `containers.*name*`.";
    };
  };
in
{
  options.my.containers = with lib.types; {
    networking = {
      bridgeName = mkOpt' str "containers" "Name of host bridge.";
      hostAddresses = mkOpt' (either str (listOf str)) "172.16.137.1/24" "Addresses for the host bridge.";
    };
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

      my.firewall.trustedInterfaces = [ cfg.networking.bridgeName ];

      systemd = {
        network = {
          netdevs."25-container-bridge".netdevConfig = {
            Name = cfg.networking.bridgeName;
            Kind = "bridge";
          };
          # Based on the pre-installed 80-container-vz
          networks."80-container-vb" = {
            matchConfig = {
              Name = "vb-*";
              Driver = "veth";
            };
            networkConfig = {
              # systemd LLDP doesn't work on bridge interfaces
              LLDP = true;
              EmitLLDP = "customer-bridge";
              # Although nspawn will set the veth's master, systemd will clear it (systemd 250 adds a `KeepMaster`
              # to avoid this)
              Bridge = cfg.networking.bridgeName;
            };
          };
          networks."80-containers-bridge" = {
            matchConfig = {
              Name = cfg.networking.bridgeName;
              Driver = "bridge";
            };
            networkConfig = {
              Address = cfg.networking.hostAddresses;
              DHCPServer = true;
              # TODO: Configuration for routed IPv6 (and maybe IPv4)
              IPMasquerade = "both";
              IPv6SendRA = true;
            };
          };
        };

        tmpfiles.rules = map (n: "d ${cfg.persistDir}/${n} 0755 root root") (attrNames cfg.instances);
      };

      containers = mapAttrs (n: c: mkMerge [
        {
          path = "/nix/var/nix/profiles/per-container/${n}";
          ephemeral = true;
          autoStart = mkDefault true;
          bindMounts = {
            "/persist" = {
              hostPath = "${cfg.persistDir}/${n}";
              isReadOnly = false;
            };
          };

          privateNetwork = true;
          hostBridge = cfg.networking.bridgeName;
          additionalCapabilities = [ "CAP_NET_ADMIN" ];
        }
        c.opts

        (mkIf config.my.build.isDevVM {
          path = mkVMOverride c.system;
          bindMounts."${devVMKeyPath}" = {
            hostPath = config.my.secrets.vmKeyPath;
            isReadOnly = true;
          };
        })
      ]) cfg.instances;
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
        # impermanence will throw a fit and bail the whole activation script if this already exists (the container
        # start script pre-creates it for some reason)
        clearMachineId.text = "rm -f /etc/machine-id";
        createPersistentStorageDirs.deps = [ "clearMachineId" ];

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
      };

      networking = {
        useHostResolvConf = false;
      };
      # Based on the pre-installed 80-container-host0
      systemd.network.networks."80-container-eth0" = {
        matchConfig = {
          Name = "eth0";
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
