{
  nixos.systems.installer = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    docCustom = false;
    rendered = config.configuration.config.my.asISO;

    configuration =
      { lib, pkgs, modulesPath, config, ... }:
      let
        inherit (lib) mkDefault mkForce mkImageMediaOverride;

        installRoot = "/mnt";
      in
      {
        imports = [
          # Useful tools to have
          "${modulesPath}/profiles/base.nix"
        ];

        config = {
          my = {
            # Lots of kernel modules and firmware
            build.allHardware = true;
            # Whatever installer mechanism is chosen will provide an appropriate `/`
            tmproot.enable = false;
            firewall.nat.enable = false;
            deploy.enable = false;
            user.enable = false;

            server.enable = true;
          };

          isoImage = {
            isoBaseName = "jackos-installer";
            volumeID = "jackos-${config.system.nixos.release}-${pkgs.stdenv.hostPlatform.uname.processor}";
            edition = "devplayer0";
            appendToMenuLabel = " /dev/player0 Installer";
          };

          environment.sessionVariables = {
            INSTALL_ROOT = installRoot;
          };
          users.users.root.openssh.authorizedKeys.keyFiles = [ lib.my.c.sshKeyFiles.deploy ];
          home-manager.users.root = {
            programs = {
              starship.settings = {
                hostname.ssh_only = false;
              };
            };

            home.shellAliases = {
              show-hw-config = "nixos-generate-config --show-hardware-config --root $INSTALL_ROOT";
            };

            my.gui.enable = false;
          };

          services = {
            openssh.settings.PermitRootLogin = mkImageMediaOverride "prohibit-password";
          };

          networking = {
            # Will be set dynamically
            hostName = "";
            useNetworkd = false;
          };

          # This should be overridden by whatever boot mechanism is used
          fileSystems."/" = mkDefault {
            device = "none";
            fsType = "tmpfs";
          };

          systemd.tmpfiles.rules = [
            "d ${installRoot} 0755 root root"
          ];
          boot.postBootCommands =
            ''
              ${pkgs.nettools}/bin/hostname "installer-$(${pkgs.coreutils}/bin/head -c4 /dev/urandom | \
                ${pkgs.coreutils}/bin/od -A none -t x4 | \
                ${pkgs.gawk}/bin/awk '{ print $1 }')"
            '';

          environment.systemPackages = with pkgs; [
            dhcpcd
            lm_sensors
            ethtool
          ];

          # Much of this onwards is yoinked from modules/profiles/installation-device.nix
          # Good to have docs in the installer!
          documentation.enable = mkForce true;
          documentation.nixos.enable = mkForce true;

          # Enable wpa_supplicant, but don't start it by default.
          networking.wireless.enable = mkDefault true;
          networking.wireless.userControlled.enable = true;
          systemd.services.wpa_supplicant.wantedBy = mkForce [];

          # Tell the Nix evaluator to garbage collect more aggressively.
          # This is desirable in memory-constrained environments that don't
          # (yet) have swap set up.
          environment.variables.GC_INITIAL_HEAP_SIZE = "1M";

          # Make the installer more likely to succeed in low memory
          # environments.  The kernel's overcommit heustistics bite us
          # fairly often, preventing processes such as nix-worker or
          # download-using-manifests.pl from forking even if there is
          # plenty of free memory.
          boot.kernel.sysctl."vm.overcommit_memory" = "1";
          services.lvm.boot.thin.enable = true;
        };
      };
  };
}
