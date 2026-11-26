#!/usr/bin/env python3
"""Evaluate, build and cache every attribute of `.#ci.<system>`.

Then point the cache's `nixfiles` profile at a link farm of the results.
CI_IFD_REQUIRED=true allows import from derivation and runs the flake check
after the builds, when the evaluation-time reference graphs are available.
Expects `nix-eval-jobs` on PATH.
"""

import json
import os
import re
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory


SYSTEM = "x86_64-linux"
PUSH = "ci/push-to-cache.sh"

# Every evaluation worker first pays for a shared evaluation of the flake (a
# few GiB), so keep workers alive for several jobs. workers * memory is the
# evaluation budget; it must leave room on the runner for Gitea and for builds
# started by import from derivation.
EVAL_WORKERS = os.environ.get("CI_EVAL_WORKERS", "4")
EVAL_WORKER_MEMORY = os.environ.get("CI_EVAL_WORKER_MEMORY", "6144")

ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")


@contextmanager
def group(title: str):
    print(f"::group::{title}")
    try:
        yield
    finally:
        print("::endgroup::")


def annotate_error(title: str, message: str):
    # Workflow commands are single lines, so escape multi-line messages
    message = ANSI_ESCAPE.sub("", message)
    for char, escape in (("%", "%25"), ("\r", "%0D"), ("\n", "%0A")):
        message = message.replace(char, escape)

    print(f"::error title={title}::{message}")


def succeeds(*command: str) -> bool:
    return subprocess.run(command).returncode == 0


def evaluate(nix_options: list[str], work: Path) -> tuple[bool, list[dict]]:
    """Evaluate every CI job, returning whether all of them evaluated."""
    result = subprocess.run(
        [
            "nix-eval-jobs", *nix_options,
            "--workers", EVAL_WORKERS, "--max-memory-size", EVAL_WORKER_MEMORY,
            "--gc-roots-dir", str(work / "gc-roots"),
            "--flake", f".#ci.{SYSTEM}",
        ],
        stdout=subprocess.PIPE,
        text=True,
    )
    jobs = [json.loads(line) for line in result.stdout.splitlines() if line]

    ok = result.returncode == 0
    for job in jobs:
        if "error" in job:
            annotate_error(f"Evaluation of {job['attrPath'][0]} failed", job["error"])
            ok = False

    return ok, [job for job in jobs if "error" not in job]


def build(jobs: list[dict]) -> tuple[bool, dict[str, str]]:
    """Build the jobs' outputs, returning whether all built and the built ones by job."""
    ok = succeeds(
        "nix", "build", "--keep-going", "--no-link",
        *(f"{job['drvPath']}^out" for job in jobs),
    )

    built = {}
    for job in jobs:
        name = job["attrPath"][0]
        path = job["outputs"]["out"]
        if succeeds("nix-store", "--check-validity", path):
            built[name] = path
        else:
            annotate_error(f"Build of {name} failed", "See the build log above.")
            ok = False

    return ok, built


def link_farm(outputs: dict[str, str], work: Path) -> str:
    """Build a link farm of the outputs from their paths, without evaluating them again."""
    outputs_file = work / "outputs.json"
    outputs_file.write_text(json.dumps(outputs))

    drv = subprocess.check_output(
        [
            "nix", "eval", "--impure", "--raw", f".#nixpkgs.unstable.{SYSTEM}",
            "--apply",
            f"""pkgs: (pkgs.linkFarm "ci" (builtins.mapAttrs (_: builtins.storePath)
              (builtins.fromJSON (builtins.readFile {json.dumps(str(outputs_file))})))).drvPath""",
        ],
        text=True,
    )

    return subprocess.check_output(
        ["nix", "build", "--no-link", "--print-out-paths", f"{drv}^out"],
        text=True,
    ).strip()


def main():
    allow_ifd = os.environ.get("CI_IFD_REQUIRED", "false") == "true"
    nix_options = ["--option", "allow-import-from-derivation", str(allow_ifd).lower()]

    with group("Collect cache garbage"):
        subprocess.run([PUSH, "--gc"], check=True)

    with TemporaryDirectory() as work:
        work = Path(work)

        with group("Evaluate"):
            ok, jobs = evaluate(nix_options, work)

        built = {}
        if jobs:
            with group("Build"):
                built_all, built = build(jobs)
            ok = ok and built_all

        # Cache whatever built, even when the run fails
        if built:
            with group("Cache"):
                subprocess.run([PUSH, *built.values()], check=True)

        if not ok:
            sys.exit(1)

        if allow_ifd:
            with group("Check flake"):
                subprocess.run(["nix", "flake", "check", *nix_options], check=True)

        with group("Update cache profile"):
            farm = link_farm(built, work)
            subprocess.run([PUSH, farm], env=os.environ | {"UPDATE_PROFILE": "1"}, check=True)


if __name__ == "__main__":
    # Keep this script's output in order with its commands'
    sys.stdout.reconfigure(line_buffering=True)
    main()
