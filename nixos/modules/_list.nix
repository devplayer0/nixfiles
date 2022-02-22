{
  nixos.modules = {
    common = ./common.nix;
    user = ./user.nix;
    build = ./build.nix;
    dynamic-motd = ./dynamic-motd.nix;
    tmproot = ./tmproot.nix;
    firewall = ./firewall.nix;
    server = ./server.nix;
    deploy-rs = ./deploy-rs.nix;
    secrets = ./secrets.nix;
  };
}
