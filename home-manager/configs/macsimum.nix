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

        home.packages = with pkgs; [
          python310
          monocraft
        ];

        programs = {
          ssh.enable = false;
          java = {
            enable = true;
            package = pkgs.jdk;
          };
        };
      };
  };
}
