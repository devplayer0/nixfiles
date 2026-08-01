#!/usr/bin/env python3
"""Render docs/reference/nixos-options.md from the `my.*` module options.

Builds the `optionsDoc` flake output (a `nixosOptionsDoc` JSON dump of the custom
`my.*` options) and renders it to a per-module table. The prose lives in the option
descriptions in `nixos/modules/`; this file is generated.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

OPTIONS_DOC_ATTR = ".#nixfiles.config.nixos.optionsDoc"
OUT = Path("docs/reference/nixos-options.md")
HEADER = "| Option | Type | Default | Description |"
SEP = "|---|---|---|---|"


def collapse(text: str) -> str:
    # Strip the flake's own /nix/store/<hash>-source/ prefix from rendered values so
    # defaults like `./.keys/deploy.pub` are stable (the hash changes every time this
    # generated file — part of the source tree — is rewritten).
    text = re.sub(r"/nix/store/[a-z0-9]{32}-source/", "", text)
    text = re.sub(
        r'<link\s+xlink:href="([^"]+)">([\s\S]+?)</link>',
        r"[\2](\1)",
        text,
    )
    return re.sub(r"\s+", " ", text).strip().replace("|", "\\|")


def render_default(entry: dict) -> str:
    if "default" not in entry:
        return "—"
    d = entry["default"]
    # A dict default is a `defaultText` / `literalExpression` (pre-rendered Nix in `text`);
    # anything else is a literal value we JSON-encode.
    if isinstance(d, dict):
        text = d.get("text")
        if text is None:
            text = json.dumps(d.get("value"))
    else:
        text = json.dumps(d)
    text = collapse(text)
    return f"`{text}`" if text else "—"


def build_options_json() -> dict:
    # `optionsDoc` builds to a derivation containing share/doc/nixos/options.json; the last
    # printed out-path is the derivation root.
    out = subprocess.run(
        ["nix", "build", "--no-link", "--print-out-paths", OPTIONS_DOC_ATTR],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip().splitlines()[-1]
    return json.loads((Path(out) / "share/doc/nixos/options.json").read_text())


def main() -> int:
    opts = build_options_json()

    by_module: dict[str, list[tuple[str, dict]]] = {}
    for key, entry in opts.items():
        decls = entry.get("declarations") or []
        # Only document options declared in this repo's modules. Some `my.*` options
        # (e.g. `my.buildAs`, which aliases `options.system.build`) pull in sub-options
        # declared in nixpkgs; their declaration paths don't exist here — skip them.
        if not decls or not Path(decls[0]).exists():
            continue
        by_module.setdefault(decls[0], []).append((key, entry))

    lines = [
        "# NixOS module options (`my.*`)",
        "",
        "> **Generated** from the module option descriptions by `nix run .#update-docs-options`;",
        "> CI keeps it current. The source of truth is the `mkOpt'` / `mkBoolOpt'` declarations in",
        "> `nixos/modules/` — edit those, not this file. For what each module is *for*, see the",
        "> [shared-modules overview](../architecture.md#shared-modules).",
        "",
    ]
    for decl in sorted(by_module):
        mod = Path(decl).stem
        if decl != "(unknown)":
            lines.append(f"## `{mod}` — [`{decl}`](../../{decl})")
        else:
            lines.append(f"## `{mod}`")
        lines += ["", HEADER, SEP]
        for key, entry in sorted(by_module[decl], key=lambda kv: kv[0]):
            lines.append(
                f"| `{key}` | {collapse(entry.get('type', ''))} | "
                f"{render_default(entry)} | {collapse(entry.get('description', ''))} |"
            )
        lines.append("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    new = "\n".join(lines).rstrip() + "\n"
    old = OUT.read_text() if OUT.exists() else ""
    if new != old:
        OUT.write_text(new)
        print(f"updated {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
