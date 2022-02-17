{ lib, pkgs, modulesPath, config, ... }:
let
  inherit (lib) mkDefault mkForce;
in
{
  imports = [
    # Lots of kernel modules and firmware
    "${modulesPath}/profiles/all-hardware.nix"
    # Useful tools to have
    "${modulesPath}/profiles/base.nix"
  ];

  # Some of this is yoinked from modules/profiles/installation-device.nix
  config = {
    my = {
      # Whatever installer mechanism is chosen will provied an appropriate `/`
      tmproot.enable = false;
      firewall.nat.enable = false;
      server.enable = true;
    };

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

    environment.systemPackages = with pkgs; [
      # We disable networking.useDHCP, so bring this in for the user
      dhcpcd
    ];
  };
}
