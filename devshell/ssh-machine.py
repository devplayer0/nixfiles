import hashlib
import json
import os
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path


CACHE = Path(".cache/ssh-machine/connections.json")
CACHE_VERSION = 2


def fingerprint():
    # The jj working-copy commit covers the snapshotted tree, even in secondary workspaces.
    if subprocess.run(["jj", "root"], capture_output=True).returncode == 0:
        return subprocess.check_output(
            ["jj", "log", "--no-pager", "--color", "never", "--no-graph", "-r", "@", "-T", "commit_id"],
            text=True,
        ).strip()

    diff = ["git", "diff", "--no-ext-diff", "--no-textconv", "--binary"]
    digest = hashlib.sha256()
    for command in (["git", "rev-parse", "HEAD"], [*diff, "HEAD", "--"], [*diff, "--cached", "--"]):
        digest.update(subprocess.check_output(command))
    return digest.hexdigest()


def load_connections(refresh):
    key = fingerprint()
    if not refresh:
        try:
            cached = json.loads(CACHE.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            cached = {}
        if (
            isinstance(cached, dict)
            and cached.get("fingerprint") == key
            and cached.get("version") == CACHE_VERSION
            and isinstance(cached.get("nodes"), dict)
        ):
            return cached["nodes"]

    print("Refreshing ssh-machine connection cache…", file=sys.stderr)
    nodes = json.loads(subprocess.check_output(
        ["nix", "eval", "--json", ".#nixfiles.config.deploy-rs.sshConnections"]
    ))
    if fingerprint() != key:
        sys.exit("Checkout changed during evaluation; retry ssh-machine.")

    CACHE.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=CACHE.parent, prefix=".connections.", delete=False
    ) as temporary:
        try:
            json.dump({"fingerprint": key, "version": CACHE_VERSION, "nodes": nodes}, temporary)
            temporary.flush()
            os.replace(temporary.name, CACHE)
        finally:
            Path(temporary.name).unlink(missing_ok=True)

    return nodes


def resolve_target(nodes, name):
    # deploy-rs mangles home configuration names containing @.
    node_name = name.replace("@", "-at-")
    if node_name in nodes:
        return nodes[node_name], None

    matches = {}
    for host, node in nodes.items():
        for container in node["containers"]:
            qualified = f"{host}.container-{container}"
            if name in (container, qualified):
                matches[qualified] = (node, container)

    if len(matches) == 1:
        return next(iter(matches.values()))
    if matches:
        sys.exit(f"Ambiguous container name: {', '.join(sorted(matches))}")
    sys.exit(f"Unknown deploy node or container: {name}")


def ssh_port(node, hostname):
    config = subprocess.run(
        ["ssh", "-G", *node["sshOpts"], f"{node['sshUser']}@{hostname}"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    if config.returncode == 0:
        for line in config.stdout.splitlines():
            key, _, value = line.partition(" ")
            if key == "port":
                return value
    return None


def select_hostname(node):
    # Check preferred addresses before starting SSH so a remote command only runs once.
    *preferred, fallback = node["hostnames"]
    for hostname in preferred:
        port = ssh_port(node, hostname)
        if port is None:
            continue
        try:
            probe = subprocess.run(
                ["nc", "-z", "--", hostname, port], timeout=2,
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except subprocess.TimeoutExpired:
            continue
        if probe.returncode == 0:
            return hostname
    return fallback


def container_command(node, container, command, tty):
    args = [
        "root", "systemd-run", "--quiet", "--wait", "--collect",
        "--expand-environment=no", "--working-directory=~",
        "--pty" if tty else "--pipe",
        f"--machine={container}", "--", "/run/current-system/sw/bin/bash", "-l",
    ]
    if command:
        # SSH joins command arguments with spaces before passing them to the remote shell.
        args += ["-c", " ".join(command)]
    return f"{node['sudo']} {shlex.join(args)}"


def main(args):
    refresh = args[:1] == ["--refresh"]
    if refresh:
        args = args[1:]
    if args[:1] == ["--help"] or (not refresh and not args):
        print("Usage: ssh-machine [--refresh] <name> [cmd ...]")
        print("       ssh-machine [--refresh] <host>.container-<name> [cmd ...]")
        print("       ssh-machine --refresh")
        return

    # Resolve deploy's relative identity path from the checkout root.
    project_root = os.environ.get("PRJ_ROOT")
    if not project_root:
        sys.exit("ssh-machine: PRJ_ROOT is unset. Enter the devshell first.")
    os.chdir(project_root)
    nodes = load_connections(refresh)
    if not args:
        return

    name, *command = args
    node, container = resolve_target(nodes, name)
    hostname = select_hostname(node)
    destination = f"{node['sshUser']}@{hostname}"

    ssh = ["ssh", *node["sshOpts"]]
    if container is not None:
        tty = not command and sys.stdin.isatty()
        if tty:
            ssh.append("-t")
        command = [container_command(node, container, command, tty)]

    os.execvp("ssh", [*ssh, destination, *command])


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
    except (OSError, ValueError) as error:
        sys.exit(f"ssh-machine: {error}")
