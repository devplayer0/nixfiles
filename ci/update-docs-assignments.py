#!/usr/bin/env python3
"""Update the consolidated network-assignment tables in docs/networking.md.

Reads nixos.allAssignments from the flake and renders assignment-key subgroups for each site
(colony / home / remote / other) between per-site `<!-- assignments: <site> -->` markers. The
hand-written Notes column is preserved, keyed by (box, assignment).
"""

import json
import re
import subprocess
import sys
from pathlib import Path

DOCS = Path("docs")
TARGET = DOCS / "networking.md"
HEADER = "| Box | IPv4 | IPv6 | Domain | Notes |"
SEP = "|---|---|---|---|---|"

# Table order; also the set of valid `<!-- assignments: <site> -->` tokens.
SITE_ORDER = ["colony", "home", "remote", "other"]

# Per-site internal domains of the remote boxes (britway=lon1, britnet=bhx1, kelder=hentai).
REMOTE_DOMAINS = ("lon1.int.nul.ie", "bhx1.int.nul.ie", "hentai.engineer")


def site_of(assignments: dict) -> str:
    """Classify a box into a site table by its assignment domain.

    Prefer the `internal` assignment's domain, else the first assignment that has one.
    """
    dom = (assignments.get("internal") or {}).get("domain")
    if not dom:
        for a in assignments.values():
            if a.get("domain"):
                dom = a["domain"]
                break
    if not dom:
        return "other"
    if dom.endswith("ams1.int.nul.ie"):
        return "colony"
    if dom == "h.nul.ie" or dom.endswith(".h.nul.ie"):
        return "home"
    if any(dom.endswith(s) for s in REMOTE_DOMAINS):
        return "remote"
    return "other"


def fmt_ip(ip: dict) -> str:
    addr = ip.get("address")
    if addr is None:
        return "—"
    parts = [f"{addr}/{ip.get('mask')}"]
    if ip.get("gateway") is not None:
        parts.append(f"gw {ip['gateway']}")
    return f"`{' '.join(parts)}`"


def find_page(box: str) -> str | None:
    """Doc page for a box (relative to docs/), if one exists."""
    for pattern in (f"{box}.md", f"{box}/README.md"):
        for p in sorted(DOCS.rglob(pattern)):
            return p.relative_to(DOCS).as_posix()
    return None


def box_cell(box: str) -> str:
    page = find_page(box)
    return f"[`{box}`]({page})" if page else f"`{box}`"


def box_name_from_cell(cell: str) -> str:
    m = re.match(r"\[`?([^`\]]+)`?\]", cell)
    return m.group(1) if m else cell.strip("`")


def parse_notes(lines: list[str]) -> dict[tuple[str, str], str]:
    """Existing Notes indexed by (box, assignment), from either table layout."""
    notes: dict[tuple[str, str], str] = {}
    assignment = None
    for line in lines:
        stripped = line.strip()
        heading = re.match(r"^####\s+`([^`]+)`$", stripped)
        if heading:
            assignment = heading.group(1)
            continue
        if not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.split("|")]
        # "| a | b | ... |" splits to ['', 'a', 'b', ..., '']
        if len(cells) >= 7 and assignment is not None:
            # Current layout: one table under each assignment heading.
            box, row_assignment, note = cells[1], assignment, cells[5]
        elif len(cells) >= 8:
            # Previous layout: one site table with an Assignment column.
            box, row_assignment, note = cells[1], cells[2], cells[6]
        else:
            continue
        # Skip header and separator rows.
        if box == "Box" or set(box) <= {"-"}:
            continue
        notes[(box_name_from_cell(box), row_assignment)] = note
    return notes


def render_site(boxes: list[str], all_assignments: dict, notes: dict) -> list[str]:
    groups: dict[str, list[tuple[str, dict]]] = {}
    for box in sorted(boxes):
        for key, a in all_assignments[box].items():
            groups.setdefault(key, []).append((box, a))

    lines: list[str] = []
    group_order = sorted(groups, key=lambda key: (key != "internal", key))
    for key in group_order:
        if lines:
            lines.append("")
        lines.extend([f"#### `{key}`", "", HEADER, SEP])
        for box, a in groups[key]:
            lines.append(
                "| "
                + " | ".join(
                    [
                        box_cell(box),
                        fmt_ip(a.get("ipv4", {})),
                        fmt_ip(a.get("ipv6", {})),
                        a.get("domain") or "—",
                        notes.get((box, key), ""),
                    ]
                )
                + " |"
            )
    return lines


def update_target(all_assignments: dict) -> bool:
    by_site: dict[str, list[str]] = {s: [] for s in SITE_ORDER}
    for box, assignments in all_assignments.items():
        if not assignments:
            continue
        by_site[site_of(assignments)].append(box)

    text = TARGET.read_text()
    lines = text.splitlines()
    marker_re = re.compile(r"^<!--\s*assignments:\s*(\S+)\s*-->$")

    # Walk the file line by line; at each `<!-- assignments: <site> -->` marker, replace
    # everything up to the matching `<!-- assignments-end -->` with a freshly rendered table
    # (carrying the hand-written Notes over), leaving all other lines untouched.
    out: list[str] = []
    i = 0
    while i < len(lines):
        m = marker_re.match(lines[i].strip())
        if not m:
            out.append(lines[i])
            i += 1
            continue
        site = m.group(1)
        end = i + 1
        while end < len(lines) and lines[end].strip() != "<!-- assignments-end -->":
            end += 1
        if end >= len(lines):
            out.append(lines[i])
            i += 1
            continue
        notes = parse_notes(lines[i + 1 : end])
        out.append(lines[i])
        out.append("<!-- assignments-start -->")
        out.extend(render_site(by_site.get(site, []), all_assignments, notes))
        out.append("<!-- assignments-end -->")
        i = end + 1

    new_text = "\n".join(out) + "\n"
    if new_text != text:
        TARGET.write_text(new_text)
        return True
    return False


def main() -> int:
    result = subprocess.run(
        ["nix", "eval", ".#nixfiles.config.nixos.allAssignments", "--json"],
        capture_output=True,
        text=True,
        check=True,
    )
    all_assignments = json.loads(result.stdout)

    if update_target(all_assignments):
        print(f"updated {TARGET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
