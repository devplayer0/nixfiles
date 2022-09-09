{
  home-manager.modules = {
    common = ./common.nix;
    gui = ./gui;
    deploy-rs = ./deploy-rs.nix;
  };
}
