{
  nixos.systems.palace.configuration = { config, ... }:
  let
    # `slop-cannon`'s vsock address; the kernel reports it for every connection from the guest
    slopCannonCid = 3;
  in
  {
    my = {
      secrets.files."palace/slop-broker-deploy.key" = {
        owner = "root";
        mode = "0400";
      };

      slop-broker = {
        enable = true;
        approvers = [ config.my.user.config.name ];

        # For coding agents, wherever they run
        policies.agent.ops = {
          # Fixed read-only commands built by the broker
          query.action = "auto";
          ssh = {
            action = "ask";
            leases = [ "5m" "1h" ];
          };
        };

        requesters.slop-cannon = {
          vsockCid = slopCannonCid;
          policy = "agent";
        };

        # Agents on `castle` connecting over SSH
        requesters.castle = {
          sshKeys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINY4Znri43VCA0gJYBbO9g72OsN3xnMYbMZ79G5tAZnr slop requester (castle)"
          ];
          policy = "agent";
        };

        # Answering requests from `castle` over SSH
        sshApprovers.castle = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAnv2y4uuABxHtk2iXhKe67W8jRIJcLrDVt9/LQaG14l slop approver (castle)" ];

        ssh = {
          enable = true;
          keyFile = config.age.secrets."palace/slop-broker-deploy.key".path;
        };
      };

      vms.instances.slop-cannon.qemuFlags = [ "device vhost-vsock-pci,guest-cid=${toString slopCannonCid}" ];
    };
  };
}
