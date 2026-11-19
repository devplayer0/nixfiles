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
        ssh = {
          enable = true;
          keyFile = config.age.secrets."palace/slop-broker-deploy.key".path;
        };
      };

      vms.instances.slop-cannon.qemuFlags = [ "device vhost-vsock-pci,guest-cid=${toString slopCannonCid}" ];
    };
  };
}
