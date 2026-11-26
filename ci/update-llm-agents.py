#!/usr/bin/env python3
"""Keep the llm-agents update PR and its package build current."""

import base64
import json
import os
import subprocess
from itertools import count
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


BASE = "master"
BRANCH = "automation/llm-agents"
REF = f"refs/heads/{BRANCH}"
TITLE = "flake: Update llm-agents"
LOCK = Path("flake.lock")
BUILD_WORKFLOW = "actions/workflows/llm-agents.yaml"


def git_output(*args: str) -> bytes:
    return subprocess.check_output(["git", *args])


def versions(lock_file: Path | None = None) -> dict[str, str]:
    command = [
        "nix", "eval", "--accept-flake-config", "--no-update-lock-file", "--json",
        ".#llmAgentPackages.x86_64-linux",
        "--apply", "builtins.mapAttrs (_: package: package.version)",
    ]
    if lock_file is not None:
        command.extend(["--reference-lock-file", str(lock_file)])

    return json.loads(subprocess.check_output(command))


def api(path: str, *, method: str | None = None, query=None, data=None):
    server = os.environ["GITHUB_SERVER_URL"].rstrip("/")
    repo = os.environ["GITHUB_REPOSITORY"]
    url = f"{server}/api/v1/repos/{repo}/{path}"
    if query is not None:
        url += "?" + urlencode(query)

    headers = {"Authorization": f"token {os.environ['GITEA_TOKEN']}"}
    payload = None
    if data is not None:
        headers["Content-Type"] = "application/json"
        payload = json.dumps(data).encode()

    request = Request(url, data=payload, headers=headers, method=method)

    try:
        with urlopen(request, timeout=30) as response:
            body = response.read()
    except HTTPError as error:
        message = error.read(4096).decode(errors="replace")
        raise RuntimeError(
            f"{request.get_method()} {path} returned HTTP {error.code}: {message}"
        ) from None

    return json.loads(body) if body else None


def find_pull_request(state: str, sort: str | None = None):
    """Return the first update PR in the listing, or None."""
    repo = os.environ["GITHUB_REPOSITORY"]
    query = {"state": state, "base_branch": BASE, "limit": 50}
    if sort is not None:
        query["sort"] = sort

    for page in count(1):
        pulls = api("pulls", query=query | {"page": page})
        if not pulls:
            return None

        for pull in pulls:
            head = pull["head"]
            if head["ref"] == BRANCH and (head["repo"] or {}).get("full_name") == repo:
                return pull


def version_changes(before: dict[str, str], after: dict[str, str]) -> list[tuple[str, str, str]]:
    return [
        (name, before.get(name, "absent"), after.get(name, "absent"))
        for name in sorted(before.keys() | after.keys())
        if before.get(name) != after.get(name)
    ]


def locked_source(lock: bytes) -> dict[str, str]:
    nodes = json.loads(lock)["nodes"]
    return nodes[nodes["root"]["inputs"]["llm-agents"]]["locked"]


def pull_request_body(
    before: dict[str, str], after: dict[str, str], base_lock: bytes, proposed_lock: bytes,
) -> str:
    rows = "\n".join(
        f"| `{name}` | {old} | {new} |" for name, old, new in version_changes(before, after)
    )

    old, new = locked_source(base_lock), locked_source(proposed_lock)
    source = f"`{old['rev'][:12]}` → `{new['rev'][:12]}`"
    if new.get("type") == "github":
        compare = f"https://github.com/{new['owner']}/{new['repo']}/compare/{old['rev']}...{new['rev']}"
        source = f"[{source}]({compare})"

    return (
        f"Updates the `llm-agents` pin ({source}). Installed package versions:\n"
        "\n"
        f"| Package | `{BASE}` | Proposed |\n"
        "| --- | --- | --- |\n"
        f"{rows}\n"
        "\n"
        "Close this PR to skip these versions; a later release opens a new one."
    )


def create_pull_request(body: str):
    return api("pulls", data={"base": BASE, "head": BRANCH, "title": TITLE, "body": body})


def close_obsolete(pull) -> None:
    if pull is None:
        return

    api(f"issues/{pull['number']}/comments", data={
        "body": f"`{BASE}` already has the latest installed llm-agents versions.",
    })
    api(f"pulls/{pull['number']}", method="PATCH", data={"state": "closed"})
    print(f"Closed the obsolete update PR {pull['html_url']}.")


def declined(after: dict[str, str], reference: Path) -> bool:
    """Check whether the most recently closed update PR rejected these versions."""
    pull = find_pull_request("closed", sort="recentclose")
    if pull is None or pull["merged"]:
        return False

    # Gitea keeps the PR's head at close time even if the branch moves on.
    subprocess.run([
        "git", "fetch", "--no-tags", "--depth=1", "origin", f"refs/pull/{pull['number']}/head",
    ], check=True)
    reference.write_bytes(git_output("show", f"FETCH_HEAD:{LOCK}"))
    if versions(reference) != after:
        return False

    print(f"Skipping the versions declined in {pull['html_url']}.")
    return True


def publish(previous: str, before: dict[str, str], after: dict[str, str]) -> str:
    changes = "\n".join(
        f"{name} {old} -> {new}" for name, old, new in version_changes(before, after)
    )

    subprocess.run(["git", "add", "--", str(LOCK)], check=True)
    subprocess.run([
        "git", "-c", "user.name=github-actions[bot]",
        "-c", "user.email=github-actions[bot]@users.noreply.github.com",
        "commit", "-m", TITLE, "-m", changes,
    ], check=True)

    # Pass the credential to Git without putting it in the remote URL.
    auth = base64.b64encode(f"oauth2:{os.environ['GITEA_TOKEN']}".encode()).decode()
    subprocess.run([
        "git", "push", f"--force-with-lease={REF}:{previous}", "origin", f"HEAD:{REF}",
    ], check=True, env=os.environ | {
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "http.extraHeader",
        "GIT_CONFIG_VALUE_0": f"Authorization: Basic {auth}",
    })

    return git_output("rev-parse", "HEAD").decode().strip()


def main() -> None:
    # Capture the tip before evaluating so the lease protects concurrent updates.
    previous = git_output("ls-remote", "origin", REF).decode().partition("\t")[0]
    if previous:
        subprocess.run(["git", "fetch", "--no-tags", "--depth=2", "origin", REF], check=True)

    base_lock = git_output("show", f"HEAD:{LOCK}")
    subprocess.run(["nix", "flake", "update", "--accept-flake-config", "llm-agents"], check=True)
    candidate_lock = LOCK.read_bytes()

    pull = find_pull_request("open")
    if candidate_lock == base_lock:
        print("The llm-agents pin is current.")
        close_obsolete(pull)
        return

    with TemporaryDirectory() as temp:
        reference = Path(temp) / LOCK.name
        reference.write_bytes(base_lock)
        before = versions(reference)
        after = versions()

        if before == after:
            print("Installed llm-agents package versions are unchanged.")
            close_obsolete(pull)
            return

        if pull is None and declined(after, reference):
            return

        pending = None
        pending_lock = None
        if previous and git_output("show", f"{previous}^:{LOCK}") == base_lock:
            pending_lock = git_output("show", f"{previous}:{LOCK}")
            reference.write_bytes(pending_lock)
            pending = after if pending_lock == candidate_lock else versions(reference)

    if pending == after:
        head, proposed_lock = previous, pending_lock
    else:
        head, proposed_lock = publish(previous, before, after), candidate_lock

    # Keep the description in step with the branch, including after master moves.
    body = pull_request_body(before, after, base_lock, proposed_lock)
    if pull is None:
        pull = create_pull_request(body)
    elif pull["body"] != body:
        api(f"pulls/{pull['number']}", method="PATCH", data={"body": body})
    print(f"Update PR {pull['html_url']}")

    # Gitea suppresses events from the Actions token. Dispatch explicitly and
    # recover on the next poll if there is still no build for this commit.
    runs = api(f"{BUILD_WORKFLOW}/runs", query={"head_sha": head, "limit": 1})
    if runs["total_count"] == 0:
        api(f"{BUILD_WORKFLOW}/dispatches", data={"ref": BRANCH})
        print(f"Queued the llm-agents build for {head[:12]}.")


if __name__ == "__main__":
    main()
