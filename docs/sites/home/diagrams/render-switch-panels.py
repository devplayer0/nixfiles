#!/usr/bin/env python3
"""Render the rack panel map and cable table from switch-ports.json."""
import html
import json
from pathlib import Path
import re
import textwrap

ROOT = Path(__file__).resolve().parent
DATA = json.loads((ROOT / "switch-ports.json").read_text())
COLORS = ["#2563eb", "#7c3aed", "#d97706", "#0891b2", "#64748b", "#16a34a", "#db2777", "#dc2626", "#92400e", "#0f766e", "#4f46e5"]
TAGS = {}
POSITIONS = {}
foreground = []
for link, color in zip(DATA["links"], COLORS):
    for end in ("from", "to"):
        TAGS[tuple(link[end])] = (link["id"], color)

svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="1580" viewBox="0 0 1440 1580" role="img" aria-labelledby="title desc">',
       '<title id="title">Home rack switch front panels and cable endpoints</title>',
       '<desc id="desc">Stream is drawn above Brian but physically sits to its left. Brian above Jim above Dave, with palace several rack units below. Socket order follows the hardware; matching letter badges identify cable ends.</desc>',
       '<style>text{font-family:system-ui,sans-serif;fill:#172033}.heading{font-weight:650;font-size:22px}.sub{fill:#526075;font-size:14px}.port{font-size:12px;font-weight:600}.small{font-size:11px}.mono{font-family:monospace}</style>']


def rect(x, y, w, h, fill, stroke="none", radius=5):
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" stroke="{stroke}"/>')


def text(x, y, value, cls="", anchor="start", color=None):
    style = f' style="fill:{color}"' if color else ""
    svg.append(f'<text x="{x}" y="{y}" class="{cls}" text-anchor="{anchor}"{style}>{html.escape(value)}</text>')


def badge(x, y, tag, color):
    rect(x - 10, y - 12, 20, 20, color, radius=4)
    text(x, y + 2, tag, "port", "middle", "white")


def chassis(y, name, height, note):
    rect(115, y, 1210, height, "#eef1f5", "#a8b2c1", 8)
    text(140, y + 28, name, "heading")
    text(1300, y + 27, note, "sub", "end")


def port(host, socket, x, y, width=46, height=27, label=True):
    start = len(svg)
    POSITIONS[(host, socket)] = (x, y, width, height)
    p = next(p for p in DATA[host]["ports"] if p["socket"] == socket)
    svg.append('<g><title>' + html.escape(f'{host} {socket}: {p["interface"]} — {p["role"]}') + '</title>')
    tag, color = TAGS.get((host, socket), (None, "#64748b"))
    rect(x - width / 2, y, width, height, "#fff", color, 3)
    rect(x - width / 2 + 6, y + 5, width - 12, height - 10, "#28364a", radius=1)
    text(x, y - 9, socket, "port mono", "middle")
    if tag:
        badge(x + width / 2 - 2, y - 9, tag, color)
    if label:
        for row, line in enumerate(textwrap.wrap(p["label"], width=8 if host == "jim" else 11)[:2]):
            text(x, y + height + 15 + row * 12, line, "small", "middle")
    svg.append('</g>')
    foreground.extend(svg[start:])
    del svg[start:]


rect(0, 0, 1440, 1580, "white", radius=0)
text(95, 38, "Home rack · physical socket map", "heading")
text(95, 64, "Front views, top to bottom. Socket positions follow the hardware; spacing and chassis widths are schematic.", "sub")
svg.append('<g transform="translate(0,330)">')
rect(330, -235, 780, 305, "#eef1f5", "#a8b2c1", 8)
text(350, -205, "stream · BROUNION R86S", "heading")
text(350, -180, "Physically left of brian; drawn above for cable routing", "sub")
text(350, -150, "DC / USB", "small")
for n, x in enumerate((600, 780, 960)):
    port("stream", f"ETH{n}", x, -135, width=60)
    text(x, -65, "Intel I225-V · 2.5G", "small", "middle")
    text(x, -48, "1G connection" if n < 2 else "Unused", "small", "middle")
for socket, x in (("SFP+ L", 650), ("SFP+ R", 890)):
    port("stream", socket, x, -12, width=70)
    text(x, 53, "ConnectX-3 · 10G SFP+", "small", "middle")
# SFP captions sit below the narrow chassis to preserve the two-row socket layout.
for x in (93, 1347):
    rect(x, 90, 9, 1080, "#dce2eb", radius=2)
    for y in range(106, 1170, 24):
        rect(x + 2, y, 5, 8, "white", radius=1)

chassis(100, "brian · USW-Pro-XG-8-PoE", 155, "8 × RJ45, then 2 × SFP+")
rect(205, 180, 10, 10, "#60a5fa", radius=5)
text(210, 218, "LED", "small", "middle")
for n in range(1, 9):
    port("brian", str(n), 320 + (n - 1) * 75, 174, width=48)
for n in (9, 10):
    port("brian", str(n), 1060 + (n - 9) * 120, 174, width=65)

chassis(340, "jim · CRS326-24G-2S+RM", 205, "3 banks of 8 RJ45 · even above odd · SFP+ at right")
rect(175, 425, 54, 29, "#28364a", "#94a3b8")
text(202, 410, "CONSOLE", "small", "middle")
for n in range(1, 25):
    col = (n - 1) // 2
    x = 285 + col * 59 + (col // 4) * 17
    port("jim", str(n), x, 476 if n % 2 else 402, width=43, height=24)
port("jim", "S1", 1134, 445, width=54)
port("jim", "S2", 1235, 445, width=54)

chassis(630, "dave · CRS504-4XQ-IN", 165, "4 QSFP28 cages · console above management at right")
for x, label in ((175, "PSU 1"), (290, "PSU 2")):
    rect(x, 680, 90, 78, "#d1d8e2", "#94a3b8")
    text(x + 45, 725, label, "sub", "middle")
for n in range(1, 5):
    x = 490 + (n - 1) * 140
    if n == 3:
        rect(x - 46, 695, 92, 29, "#fff", "#0891b2")
        rect(x - 38, 701, 76, 17, "#28364a", radius=1)
        text(x, 686, "Q3", "port mono", "middle")
        text(x, 743, "4 × 10G breakout", "small", "middle")
        svg.append(f'<path d="M{x} 757 V820" stroke="#0891b2" stroke-width="2" fill="none"/>')
    else:
        port("dave", f"Q{n}", x, 695, width=92)
rect(1095, 690, 54, 27, "#28364a", "#94a3b8")
text(1122, 681, "CONSOLE", "small", "middle")
port("dave", "MGMT", 1122, 741, width=54, height=24, label=False)
text(1235, 725, "DC / reset", "sub", "middle")

rect(430, 820, 820, 84, "#f4f8fc", "#b9cadb")
text(445, 841, "Q3 breakout lanes (one physical cage)", "sub")
for n in range(1, 5):
    start = len(svg)
    p = next(p for p in DATA["dave"]["ports"] if p["socket"] == f"Q3.{n}")
    x = 485 + (n - 1) * 200
    tag, color = TAGS.get(("dave", p["socket"]), (None, "#64748b"))
    text(x, 870, p["socket"], "port mono")
    if tag:
        badge(x + 61, 866, tag, color)
    text(x, 889, p["label"], "small")
    rect(x + 83, 854, 34, 20, "white", color, radius=3)
    rect(x + 89, 860, 22, 8, color, radius=1)
    POSITIONS[("dave", p["socket"])] = (x + 100, 854, 34, 20)
    foreground.extend(svg[start:])
    del svg[start:]

text(720, 963, "⋮  several rack units  ⋮", "sub", "middle")
chassis(1030, "palace", 160, "NIC endpoints only; rear-panel positions are not depicted")
for x, name in ((350, "uplink-dave"), (730, "host-jim"), (1110, "river-jim-phy")):
    start = len(svg)
    tag, color = TAGS[("palace", name)]
    rect(x - 145, 1090, 290, 76, "white", color)
    text(x - 118, 1120, name, "port mono")
    badge(x + 119, 1114, tag, color)
    spec = next(p for p in DATA["palace"]["ports"] if p["socket"] == name)
    text(x, 1146, spec["nic"] + " · " + spec["capacity"], "small", "middle")
    POSITIONS[("palace", name)] = (x, 1090, 290, 76)
    foreground.extend(svg[start:])
    del svg[start:]


def anchor(host, socket, side="bottom"):
    x, y, w, h = POSITIONS[(host, socket)]
    return {"top": (x, y), "bottom": (x, y + h),
            "left": (x - w / 2, y + h / 2), "right": (x + w / 2, y + h / 2)}[side]


def cable(tag, points):
    color = COLORS[ord(tag) - ord("A")]
    points = " ".join(f"{x},{y}" for x, y in points)
    svg.append(f'<polyline points="{points}" fill="none" stroke="white" stroke-width="7" stroke-linejoin="round" stroke-linecap="round"/>')
    svg.append(f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>')


cable("A", [anchor("brian", "9"), (1060, 280), (38, 280), (38, 925),
            (785, 925), anchor("dave", "Q3.2")])
cable("B", [anchor("brian", "10"), (1180, 300), (58, 300), (58, 950),
            (1185, 950), anchor("dave", "Q3.4")])
cable("C", [anchor("brian", "5"), (620, 315), (492, 315), (492, 458),
            (462, 458), anchor("jim", "7", "top")])
cable("D", [anchor("jim", "S1"), (1134, 575), (1394, 575), (1394, 975),
            (585, 975), anchor("dave", "Q3.1")])
cable("E", [anchor("jim", "24", "right"), (1010, 414), (1010, 600),
            (1380, 600), (1380, 753), anchor("dave", "MGMT", "right")])
cable("F", [anchor("jim", "5"), (403, 568), (1368, 568), (1368, 1010),
            (730, 1010), anchor("palace", "host-jim", "top")])
cable("G", [anchor("jim", "22", "right"), (940, 414), (940, 590),
            (1416, 590), (1416, 1025), (1110, 1025), anchor("palace", "river-jim-phy", "top")])
cable("H", [anchor("dave", "Q1"), (490, 790), (410, 790), (410, 1000),
            (350, 1000), anchor("palace", "uplink-dave", "top")])

cable("I", [anchor("stream", "ETH0", "top"), (600, -160), (18, -160),
            (18, 555), (898, 555), anchor("jim", "21")])
cable("J", [anchor("stream", "ETH1", "top"), (780, -170), (70, -170),
            (70, 322), (403, 322), anchor("jim", "6", "top")])
cable("K", [anchor("stream", "SFP+ R"), (890, 80), (1428, 80),
            (1428, 920), (985, 920), anchor("dave", "Q3.3")])

svg.extend(foreground)

text(95, 1220, "Matching letter badges identify cable ends. Port labels describe configured use; they do not indicate current link state.", "sub")
svg.append('</g></svg>')
(ROOT / "switch-panels.svg").write_text('\n'.join(svg) + '\n')

rows = ["| Cable | Endpoint | Endpoint | Connection |", "|---|---|---|---|"]
for link in DATA["links"]:
    ends = [f'`{link[end][0]}` `{link[end][1]}`' for end in ("from", "to")]
    rows.append(f'| **{link["id"]}** | {ends[0]} | {ends[1]} | {link["description"]} |')
page = ROOT.parent / "switches.md"
content = page.read_text()
start, end = "<!-- switch-cables -->", "<!-- /switch-cables -->"
if start in content:
    content = re.sub(re.escape(start) + r'.*?' + re.escape(end),
                     start + '\n' + '\n'.join(rows) + '\n' + end, content, flags=re.S)
    page.write_text(content)
