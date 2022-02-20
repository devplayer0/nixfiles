{
  home-manager.modules = {
    common = ./common.nix;
    gui = ./gui.nix;
    deploy-rs = ./deploy-rs.nix;
  };
}
