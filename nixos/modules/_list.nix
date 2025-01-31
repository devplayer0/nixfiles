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
    containers = ./containers.nix;
    vms = ./vms.nix;
    network = ./network.nix;
    pdns = ./pdns.nix;
    nginx-sso = ./nginx-sso.nix;
    gui = ./gui;
    l2mesh = ./l2mesh.nix;
    borgthin = ./borgthin.nix;
    nvme = ./nvme;
    spdk = ./spdk.nix;
    librespeed = ./librespeed;
    netboot = ./netboot;
  };
}
