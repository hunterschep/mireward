# T10 landmark structures and collision

Status: IMPLEMENTED; focused geometry and walking probes VERIFIED. Full exterior navigation/render checks remain with T10 integration.
Repository checkpoint: working-tree helper and handoff; no Git mutations from this subtask.

## Delivered

`ExteriorLandmarks.build(parent: Node3D, manifest: Dictionary) -> Dictionary` creates one root for every canonical landmark and returns roots keyed by StringName landmark IDs. Each structure uses its absolute manifest position relative to that landmark root, the authored yaw, and the requested visual scale. The current manifest builds nine roots and 24 structures.

The helper consumes `manifest.landmarks` and `manifest.exterior.structures`, using only existing VisualFactory building/prop assets. Entries contain `id`, `landmark_id`, `category`, `family`, `position`, `yaw`, `scale`, and `collision`. `validate(manifest) -> PackedStringArray` rejects malformed transforms, unknown art/collision combinations, duplicate identities, and broken landmark references before construction. `build` reports invalid input and returns an empty dictionary.

Owned files are `scripts/world/exterior_landmarks.gd` and this handoff. The helper adds no players, enemies, NPCs, interactive containers, quest handlers, or navigation regions. It does not alter the map or art resources.

## Geometry contract

- House, inn, forge, keep, and tower shells match T03 wall dimensions. Their front faces remain -Z before authored yaw. Separate side/rear/front-flank/header colliders preserve the doorway instead of filling the building footprint.
- Shell floors are 0.12 meters high before scaling. Short convex threshold ramps permit ordinary walking entry. The forge hearth has its own small collider.
- Gates/monastery arches retain the full three-meter base opening, scaled with the structure. The crypt arch therefore has its authored 4.5-meter opening. Road-gate footings remain outside the opening.
- Tent side fabric, roof, rear fabric, and entrance poles have matching simple collision while the entrance stays open.
- Ferry/bridge decks have walkable floors and side rails, with low ramps at both Z approaches. Ferry collision includes its real central mast; the two side aisles remain open.
- Walls are solid within their authored ground footprint. Kiln collision uses the requested two-meter radius. Tree collision covers trunks only. Rock/cart/well/shrine collision uses grounded footprints rather than canopy/decorative bounds.
- StaticBody3D nodes remain unscaled. Box dimensions/offsets and convex vertices receive the manifest scale directly, including nonuniform scaling. Bodies use the world layer with player/hostile/neutral masks.
- Keep and both tower families retain visibility to 700 meters; ordinary structures and props use 220 meters with a 20-meter visibility margin. Culling affects visuals only.

The helper treats manifest coordinates as parent-local world coordinates. The exterior parent should retain the normal unit scale. Each returned root and structure carries stable landmark/structure metadata for runtime lookup; these node references are not persistence data.

## Verification actually performed

Pinned Godot: `4.5.2.stable.official.6ce3de25a` on the provided macOS host.

- `Godot --headless --path . --editor --quit`: exit 0, clean helper import with the new exterior scripts.
- Temporary `/tmp/mireward-landmark-probe.gd`: **245 checks, zero failures**. Instantiated the current nine landmarks/24 structures; checked placement, visibility distances, world layers and unit-scale collision bodies; tested player-capsule clearance at shell/tent/gate entrances and ferry approaches; verified solid shell sides, all three paired exterior return anchors, and every authored exterior hostile spawn anchor; rejected duplicate structures and zero scale.
- `Godot --headless --path . --script res://tests/run_all.gd -- --suite=/tmp/mireward-landmark-walk-probe.gd`: **three assertions passed**, zero failed suites. The actual MirePlayer scene walked from ground level onto the inn floor, scaled keep floor, and ferry deck without jumping. Final local floor heights were approximately 0.120, 0.241, and 0.321 meters.

The initial direct launch of the absolute walking probe produced an autoload-dependent compilation error despite printing movement results. Those results were not accepted as clean verification. The same checks were converted to a RefCounted suite and rerun through the public runner above, which passed without engine/script errors.

## Successor checks

T10 integration owns full terrain/navigation baking, route travel, and native rendered inspection. Preserve the paired return transforms and the reserved spawn/interaction corridors when adjusting placements. The temporary probe scripts were left in `/tmp` for incorporation into the integration owner's formal world suite; they are not shipped runtime files. No native window was controlled by this subtask.
