#!/usr/bin/env python3
"""Update assignment tables in docs/ from nixos.allAssignments."""

import json
import re
import subprocess
import sys
from pathlib import Path

DOCS_DIR = Path("docs")
HEADER = "| Name | Assignment | IPv4 | IPv6 | Domain | Notes |"


def fmt_ip(ip: dict) -> str:
    addr = ip.get("address")
    if addr is None:
        return "—"
    mask = ip.get("mask")
    gateway = ip.get("gateway")
    parts = [f"{addr}/{mask}"]
    if gateway is not None:
        parts.append(f"gw {gateway}")
    return f"`{' '.join(parts)}`"


def parse_notes(lines: list[str]) -> dict[str, str]:
    """Extract existing Notes indexed by Assignment from a marked table."""
    notes: dict[str, str] = {}
    for line in lines:
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.split("|")]
        # Splitting "| a | b |" produces ['', 'a', 'b', '']
        if len(cells) < 8:
            continue
        key = cells[2]
        if key == "Assignment":
            continue
        notes[key] = cells[6]
    return notes


def render_table(assignments: dict, notes: dict[str, str]) -> list[str]:
    lines = [
        HEADER,
        "|---|---|---|---|---|---|",
    ]
    for key, a in assignments.items():
        name = a.get("name", key)
        alt = ", ".join(a.get("altNames", []))
        if alt:
            name = f"{name} ({alt})"
        lines.append(
            "| "
            + " | ".join(
                [
                    name,
                    key,
                    fmt_ip(a.get("ipv4", {})),
                    fmt_ip(a.get("ipv6", {})),
                    a.get("domain") or "—",
                    notes.get(key, ""),
                ]
            )
            + " |"
        )
    return lines


def process_file(path: Path, all_assignments: dict) -> bool:
    box_name = path.stem
    if box_name not in all_assignments:
        return False

    text = path.read_text()
    lines = text.splitlines()

    marker_re = re.compile(r"^<!--\s*assignments:\s*(\S+)\s*-->$")
    for i, line in enumerate(lines):
        m = marker_re.match(line.strip())
        if m and m.group(1) == box_name:
            end_idx = None
            for j in range(i + 1, len(lines)):
                if lines[j].strip() == "<!-- assignments-end -->":
                    end_idx = j
                    break
            if end_idx is None:
                return False

            old_inner = lines[i + 1 : end_idx]
            notes = parse_notes(old_inner)
            new_table = render_table(all_assignments[box_name], notes)
            new_lines = (
                lines[: i + 1]
                + ["<!-- assignments-start -->"]
                + new_table
                + ["<!-- assignments-end -->"]
                + lines[end_idx + 1 :]
            )
            if new_lines != lines:
                path.write_text("\n".join(new_lines) + "\n")
                return True
            return False

    return False


def main() -> int:
    result = subprocess.run(
        ["nix", "eval", ".#nixfiles.config.nixos.allAssignments", "--json"],
        capture_output=True,
        text=True,
        check=True,
    )
    all_assignments = json.loads(result.stdout)

    changed = False
    for path in sorted(DOCS_DIR.rglob("*.md")):
        if process_file(path, all_assignments):
            print(f"updated {path}")
            changed = True

    return 1 if changed else 0


if __name__ == "__main__":
    sys.exit(main())
