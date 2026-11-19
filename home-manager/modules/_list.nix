{
  home-manager.modules = {
    common = ./common.nix;
    gui = ./gui;
    agents = ./agents;
    slop = ./slop.nix;
    deploy-rs = ./deploy-rs.nix;
    swaync = ./swaync.nix;
  };
}
