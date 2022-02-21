{
  home-manager.homes."jack@macsimum" = {
    system = "x86_64-darwin";
    nixpkgs = "unstable";
    homeDirectory = "/Users/jack";
    username = "jack";

    configuration = { pkgs, ... }:
      {
        my = {
          deploy.enable = false;
          nix.config.cores = "6";
        };

        programs = {
          ssh.enable = false;
        };
      };
  };
}
