# MIREWARD

A first-person medieval RPG in development. The complete design, requirements, and execution plan are in [design.md](design.md), [requirements.md](requirements.md), and [tasks.md](tasks.md).

## Engine and launch

Use **Godot 4.5.2.stable**, standard GDScript edition, with matching **4.5.2.stable** export templates. Compatibility rendering and 60 Hz physics are required. No addons, Blender, paid assets, or runtime service are needed.

Import `project.godot` in that editor, then press F6 on the main scene or F5 to run the project. From the project directory, with the pinned executable available as `godot`:

```sh
godot --headless --path . --import
godot --path .
godot --headless --path . --script res://tools/validate_content.gd
godot --headless --path . --script res://tests/run_all.gd
```

The current checkpoint includes combat, inventory, quests, dialogue, connected worlds, durable saves, and functional game menus. The opening characters and cart encounter are connected; their native acceptance run is next. It is not yet a complete playable campaign or release. See [progress](docs/progress.md) and [verification](docs/verification.md) for the active work queue and actual evidence.

## Default controls

WASD move, mouse look, Shift sprint, Space jump, left mouse light attack, R heavy attack, right mouse shield, E interact, Q bandage, Tab inventory, J journal, M map, Escape back/pause.

## Local delivery

Export presets exist for macOS (universal, local ad-hoc signature), Windows (x86_64), and Linux (x86_64). Create the destination directory and use the exact preset name:

```sh
mkdir -p builds
godot --headless --path . --export-release macOS builds/MIREWARD.app
```

The release export is not yet verified. The environment's standalone template probe is recorded separately in [T01 environment](docs/handoffs/T01-environment.md). macOS notarization and distribution signing are outside this local delivery.

No publishing is planned. Source, original assets, tests, host export, accessibility controls, save locations, credits, and release verification will be documented as their task gates are integrated. Mandatory unfinished features remain open in [traceability](docs/traceability.md).
