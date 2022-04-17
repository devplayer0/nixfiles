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
        };

        nix.settings.cores = 6;

        programs = {
          ssh.enable = false;
        };
      };
  };
}
