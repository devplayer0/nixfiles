{
  home-manager.modules = {
    common = ./common.nix;
    gui = ./gui;
    agents = ./agents;
    deploy-rs = ./deploy-rs.nix;
    swaync = ./swaync.nix;
  };
}
