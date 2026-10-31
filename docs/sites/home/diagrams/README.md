# Home network diagrams

`switch-ports.json` holds the socket inventory, NIC capacities and cable endpoints. Regenerate
`switch-panels.svg` and the cable table in `../switches.md` from the repository root:

```sh
python3 docs/sites/home/diagrams/render-switch-panels.py
```

The renderer uses only the Python standard library. Socket geometry and schematic cable routing
live in the renderer. Keep the inventory and routing together when adding a connection.

`home-fabric.mmd` is the Mermaid source for the logical fabric diagram. Render it with Mermaid
CLI (the checked-in SVG was rendered with Mermaid 11.12.0):

```sh
mmdc -i docs/sites/home/diagrams/home-fabric.mmd -o docs/sites/home/diagrams/home-fabric.svg
```

Check rendered SVGs visually after editing. Both diagrams are checked in so Markdown viewers
can show them without Mermaid support.
