{
  home-manager.homes."jack@macsimum" = {
    system = "x86_64-darwin";
    nixpkgs = "mine";
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
