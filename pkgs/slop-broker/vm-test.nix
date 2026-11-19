# Runs the broker through the `my.slop-broker` module, with its real service hardening, over vsock
# loopback, against a local sshd. Build it as `slop-broker.tests.vm` (see `docs/slop-broker.md`).
{ pkgs }:
let
  inherit (pkgs) lib;

  key = pkgs.runCommand "test-key" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir $out && ssh-keygen -q -t ed25519 -N "" -f $out/key
  '';
in
pkgs.testers.runNixOSTest {
  name = "slop-broker";
  # The module uses `lib.my` and the flake's deploy nodes; `pkgs.lib` has the former, and the
  # SSH targets below replace the latter.
  node.specialArgs = {
    inherit lib;
    self.deploy.nodes = { };
  };
  nodes.machine = { ... }: {
    imports = [ ../../nixos/modules/slop-broker.nix ];
    # Declared by the box modules this test leaves out
    options.my.tmproot = lib.mkOption { type = lib.types.anything; default = { }; };

    config = {
      boot.kernelModules = [ "vsock_loopback" ];
      services.openssh.enable = true;
      users.users.deploy = { isNormalUser = true; openssh.authorizedKeys.keyFiles = [ "${key}/key.pub" ]; };
      users.users.reviewer.isNormalUser = true;
      users.users.agent.isNormalUser = true;
      environment.systemPackages = [ pkgs.util-linux ];
      # Not a store path, as the module requires
      environment.etc."slop-broker-test/key".source = "${key}/key";

      my.slop-broker = {
        enable = true;
        approvers = [ "reviewer" ];

        policies.agent.ops = {
          query.action = "auto";
          ssh = { action = "ask"; leases = [ "5m" ]; rules = [ { match.target = "denied"; action = "deny"; } ]; };
        };
        requesters.agent = {
          vsockCid = 1;
          policy = "agent";
        };
        ssh = {
          enable = true;
          keyFile = "/etc/slop-broker-test/key";
          targets = lib.genAttrs [ "local" "other" "denied" ] (_: { hostname = "localhost"; user = "deploy"; });
        };
      };
    };
  };
  testScript = ''
    machine.wait_for_unit("sshd.service")
    machine.wait_for_unit("slop-broker.service")
    machine.wait_for_file("/run/slop-broker/approve.sock")
    env = "SLOP_BROKER=vsock:1:6262 SLOP_LABEL='vm test'"

    # Denied by policy, without asking
    status, out = machine.execute(f"su agent -c \"{env} slop ssh denied -- true\" 2>&1")
    assert status == 125 and "denied by policy" in out, (status, out)

    # Fixed queries run without asking
    out = machine.succeed(f"su agent -c \"{env} slop status local sshd.service\"")
    assert "sshd.service" in out, out
    out = machine.succeed(f"su agent -c \"{env} slop logs local sshd.service -n 5 --since 1h\"")
    print(out)

    # Ask, approve from a terminal, and see the real ssh run
    machine.execute(f"su agent -c \"{env} slop ssh local -- 'echo hi from \\$(whoami)'\" > /tmp/out 2>&1 &")
    machine.wait_until_succeeds("su reviewer -c 'slop-approve list' | grep -q 'ssh local'")
    listing = machine.succeed("su reviewer -c 'slop-approve list'")
    print(listing)
    assert "vm test" in listing
    request = listing.split()[0][:4]
    status, out = machine.execute("su agent -c 'slop-approve " + request + " once' 2>&1")
    assert status != 0, out
    machine.succeed(f"su reviewer -c 'slop-approve {request} 5m'")
    machine.wait_until_succeeds("grep -q 'hi from deploy' /tmp/out")
    out = machine.succeed("cat /tmp/out")
    print(out)
    assert "Permanently added" not in out, out

    # Covered by the lease now; stdin is forwarded
    out = machine.succeed(f"echo piped | su agent -c \"{env} slop ssh local -- cat\"")
    assert "piped" in out, out
    out = machine.succeed(f"su agent -c \"{env} slop requests\"")
    assert "ssh" in out and "lease" in out, out

    # Unknown nodes are named plainly; usage errors exit 125 like other refusals
    status, out = machine.execute(f"su agent -c \"{env} slop ssh nope -- true\" 2>&1")
    assert status == 125 and "unknown node nope;" in out, (status, out)
    status, out = machine.execute(f"su agent -c \"{env} slop ssh\" 2>&1")
    assert status == 125, (status, out)

    # Interactive answering on a terminal
    machine.execute(f"su agent -c \"{env} slop ssh other -- echo interactive\" > /tmp/out2 2>&1 &")
    machine.wait_until_succeeds("su reviewer -c 'slop-approve list' | grep -q 'ssh other'")
    out = machine.succeed("(sleep 1; echo x; sleep 1; echo o) | timeout 5 su reviewer -c \"script -qec slop-approve /dev/null\" || true")
    print(out)
    assert "Not an option" in out and "Recorded: once" in out, out
    machine.wait_until_succeeds("grep -q interactive /tmp/out2")

    # The only pending request can be answered without its ID
    machine.execute(f"su agent -c \"{env} slop ssh other -- true; echo \\$?\" > /tmp/out3 2>&1 &")
    machine.wait_until_succeeds("su reviewer -c 'slop-approve list' | grep -q 'ssh other'")
    machine.succeed("su reviewer -c 'slop-approve deny'")
    machine.wait_until_succeeds("grep -q 'denied by approver' /tmp/out3")
    machine.wait_until_succeeds("grep -qx 125 /tmp/out3", timeout=30)

    audit = machine.succeed("su reviewer -c 'slop-approve log'")
    print(audit)
    assert "agent asks: ssh local" in audit and "answered 5m by reviewer" in audit, audit
  '';
}
