# T07 navigation arena fixture

Status: VERIFIED for import, actual navigation route, geometry-only isolation, and populated headless startup. Visual/input inspection remains UNVERIFIED.

## Delivered

`scenes/actors/navigation_arena.tscn` instantiates `NavigationArena` from `scripts/ai/navigation_arena.gd`. Public properties: `populate: bool = true`, `region: NavigationRegion3D`, and `obstacle: StaticBody3D`. The `navigation_ready` signal fires once synchronization is usable.

The fixed floor is 40 × 40 meters with physical world collision. The centered obstacle is at (0, 1.5, 0), size (4, 3, 2). Eight manually authored, edge-sharing navigation polygons surround the omitted center cell. The hole spans X ±2.5 and Z ±1.5, providing 0.5-meter obstacle clearance; outer navigation edges stay 0.5 meters inside the floor. Nothing rebakes during play. Floor and wall use the shared low-poly art/material toolkit.

Set `populate=false` before adding the node to the tree. This creates only Ground, Obstacle, and NavigationRegion children, without changing GameSession or creating a player, coordinator, UI, or enemies. Tests should await `arena.navigation_ready` immediately after adding it.

With `populate=true`, the fixture starts a fresh session, places the real player at (0, 0, 9), configures GameModeController and ModalHost, and creates EncounterCoordinator. Four EnemyActor instances use copied canonical spawn records, retain their original stable IDs/archetypes, and receive fixture positions: cutpurse (0, 0, -7), spearman (-8, 0, -5), raider (8, 0, -5), keeper (0, 0, -12). They face the player. Each actor is added before configure and registers itself with the coordinator. The fixture connects danger_changed to GameSession.danger and displays mapped control labels.

## Verification actually performed

Pinned Godot `4.5.2.stable.official.6ce3de25a`, macOS arm64:

```sh
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . res://scenes/actors/navigation_arena.tscn -- --verify-navigation
"$GODOT" --headless --path . res://scenes/actors/navigation_arena.tscn --quit-after 120
```

Final commands exited 0 without parse/runtime warnings or errors. `--verify-navigation` selects geometry-only mode and checks an actual NavigationServer path, each path segment against collision and a 0.4-meter expanded obstacle, the blocked direct ray, and absence of population. Result:

```text
NAVIGATION_ARENA_RESULT {"geometry_only":true,"map_iteration":2,"ok":true,"route":[[0.0,0.0,9.0],[-2.5,0.0,1.5],[-2.5,0.0,-1.5],[0.0,0.0,-9.0]],"wall_blocks_direct_ray":true}
```

Initial testing exposed that map iteration 1 can exist before the new region has usable polygons. Waiting for map iteration alone returned an empty path. Readiness now requires positive map and region iterations plus ownership of the spawn's closest navigation point by this region, with a 120-physics-frame failure bound. The final route above verifies the correction. Logs: `/tmp/mireward-t07-arena-{import,route,populated}.log`.

## Scope and remaining gates

Only the two assigned arena files and this handoff were authored; Godot generated the script UID during import. AI/coordinator behavior and enemy tests remain with the T07 owner. No native UI, mouse, or keyboard was touched. Populated startup is not visual, combat, navigation-following, or crowd-behavior proof. The fixture is not campaign content.
