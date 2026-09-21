# T03 building and environment catalog

Status: IMPLEMENTED; headless geometry verified; visual inspection delegated to T03 integration.
Repository checkpoint: working tree, `scripts/art/art_buildings.gd`.

## Behavior delivered

Original, deterministic low-poly architecture in the D08 Greyfen palette. Houses have open doorways, hollow occupied rooms, timber frames, window mullions, layered roof courses, stone footings, and chimneys. The inn adds its green roof and waterwheel; the forge adds a hooded ember hearth. Gates use assembled arch stones and the red levy banner. The keep has parapets, buttresses, and arrow slits. Monastery and watchtower silhouettes have distinct intact bellwork and broken masonry. Crypt and undercroft rooms contain burial plinths or timber storage shelves. Bridges and ferries have individual deck boards and rails. Tents use striped canvas with clear entrance space. The black kiln has a firing mouth and smoke vent.

Supports R41 and R52. Every family is original local geometry, with no downloaded models, textures, licenses, or runtime dependencies.

## Changed files and contracts

- `scripts/art/art_buildings.gd`: `ArtBuildings.FAMILIES: Array[StringName]`; `static make(family: StringName) -> Node3D`.
- `docs/handoffs/T03-buildings.md`: this handoff.

Family IDs: `cottage`, `inn`, `forge`, `road_gate`, `wall`, `keep`, `monastery_arch`, `monastery_tower`, `crypt_room`, `undercroft_room`, `bridge`, `ferry`, `ruined_watchtower`, `tent`, `kiln`.

All outputs face -Z, use meter scale, and have their lowest geometry at y=0. No physics body, interaction, script, or collision ownership is included. ArtMesh owns materials and mesh creation. The parent factory may batch these meshes without changing the catalog API.

| Family | Dimensions and entrance contract |
|---|---|
| Cottage / forge | Shell 5.8 x 5.4 m; front z=-2.7; doorway 1.6 m wide, 2.38 m clear above the 0.12 m floor |
| Inn | Shell 6.6 x 7.6 m; front z=-3.8; same doorway; exterior waterwheel extends beyond shell |
| Keep | Shell 7.6 x 8 m; front z=-4; doorway 2 m wide |
| Monastery / ruined tower | Shell 5 x 5 m; front z=-2.5; doorway 1.6 m wide |
| Crypt / undercroft room | Shell 10 x 10 m; front z=-5; doorway 2.2 m wide; floor top 0.12 m plus shallow flagstones |
| Road gate | Full 3 m clear opening, including footings; centered on z=0 |
| Bridge / ferry | Decks 3 x 10 m / 3 x 5 m; deck top 0.32 m; approaches at both Z ends |
| Tent | 4.2 x 4.2 m; front z=-2.1; clear central entrance at least 1.3 x 2.3 m |
| Kiln | Decorative furnace, not a habitable room; low firing mouth faces -Z |

## Verification actually performed

Pinned executable: Godot 4.5.2 stable, official build `6ce3de25a`.

- Ran `Godot --headless --path . --editor --import --quit`: exit 0, no parse or import failures.
- Ran a temporary geometry probe using `Godot --headless --path . --script /tmp/mireward_building_geometry_check.gd`: exit 0. Instantiated all 15 families and checked 686 material-bearing meshes. No empty meshes, missing materials, collision bodies, or vertices below y=0.
- The same probe tested 90 segment rays through ten front entrances: left/center/right at heights 0.3, 1.65, and 2.3 m. All were clear. Standard probes span 1.3 m width; the gate probe spans 2.9 m width inside its full 3 m opening.
- Reviewed the complete owned source for scope, deterministic construction, and doorway obstructions.

## Remaining gaps

First-person and 540p visual screenshots are UNVERIFIED in this handoff. T03 integration owns showcase generation/render inspection. These visual-only meshes do not establish collision-safe traversal; T10/T11 must place matching wall, floor, doorway, and navigation shapes. The furnace opening is intentionally too low to enter.

## Successor instructions

Instantiate through the parent ArtFactory or call `ArtBuildings.make(id)`. Place the returned root at the terrain height. Add collision around shell surfaces, keeping doorway gaps and room floor elevations above. Avoid a solid bounding-box collider for any entered building. Use shell dimensions, not the decorative roof/waterwheel bounds, when making those colliders. Keep the keeper-room center clear for combat and use the existing aisle between the burial plinths.
