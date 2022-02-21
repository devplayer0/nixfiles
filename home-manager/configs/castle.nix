{
  home-manager.homes."dev@castle" = {
    system = "x86_64-linux";
    nixpkgs = "unstable";
    homeDirectory = "/home/dev";
    username = "dev";

    configuration = { pkgs, ... }:
      {
        # So home-manager will inject the sourcing of ~/.nix-profile/etc/profile.d/nix.sh
        targets.genericLinux.enable = true;

        my = {
          deploy.node = {
            hostname = "h.nul.ie";
            sshOpts = [ "-4" "-p" "8022" ];
          };
          nix.config.cores = "16";
        };

        programs = {
          ssh.matchBlocks = {
            home = {
              host =
                "vm keep.core fw firewall moat.vm storage cellar.vm lxd ship.vm docker whale.vm kerberos gatehouse.lxd " +
                "nginx.lxd upnp.lxd souterrain.lxd drawbridge.lxd mailcow.lxd";
              user = "root";
            };
          };

          kakoune.enable = true;
        };
      };
  };
}
