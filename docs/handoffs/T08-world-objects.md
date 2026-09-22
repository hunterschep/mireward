# T08 physical loot and readable adapters

Status: VERIFIED headless adapter integration. World placement and native presentation remain T16/T17/T23 work.
Repository checkpoint: owned working-tree files; root owns commits and pushes.

## API and construction

`scripts/world/world_object.gd` defines `WorldObject`, a StaticBody3D with visible local art and an `InteractionComponent`.

```gdscript
var object := WorldObject.new()
world.add_child(object)
object.position = authored_position
object.rotation.y = authored_yaw
var result := object.configure(source_id, &"loot", candidate_snapshot)
# After a successful world commit:
object.activate()
```

Public methods are `configure(source_id: StringName, kind: StringName, snapshot: Dictionary) -> ActionResult`, `apply_persistent_state(record: Dictionary) -> ActionResult`, `activate() -> ActionResult`, and `deactivate() -> void`. Kind is `loot` or `readable`. Configuration runs once after tree attachment, using the supplied detached snapshot. Keep body scale at one; position/yaw belong to the world factory. Check failed setup results and discard the failed world/object.

Construction and persistent-state application create no saved state or live listeners. Activation refreshes from committed state and subscribes once to relevant inventory/currency/defeat/restore events. Deactivation and tree exit disconnect listeners and disable interaction. Tree re-entry requires explicit activation. Geometry remains present for prepared-world collision/navigation checks.

## Sources and actions

All thirteen canonical fixed containers select existing medicine chest, ledger chest, seal chest, badge locker, crate, barrel, candle or ring art. Crates gain an articulated lid; ring offerings use a small local stone pedestal/bowl. Open lids and dark interiors identify opened/depleted permanent containers. Collected candle meshes and rings disappear; the ring pedestal remains. Empty permanent containers remain visible and return an honest empty loot view. No new persistent IDs are introduced.

Canonical hostile spawn IDs produce a purse using `corpse_loot` art. It has no movement collision, appears only after defeat when loot remains, and disappears when emptied. If an EnemyActor and purse coexist, the actor retains `world.entities[spawn_id]`; the purse uses the same source ID without replacing that registry entry or inventing another loot source. Configure its candidate state separately and activate it with the world. The encounter owner positions the purse beside the actual fallen actor. A sibling avoids inheriting a disabled actor's visibility; a loot-only restored representation may instead be the sole registry owner for the canonical ID.

Readables accept every `QuestService.DOCUMENTS` ID. They use signs, paper/book stands, stone inscriptions and the existing writ table. Small added meshes use existing ArtMesh primitives/materials and project-authored art; no external asset dependency was added.

| Interaction | Result payload | Authority |
|---|---|---|
| Open loot | `ui_action: "loot", entity_id, label` | Checks current gates, records `opened=true` once under `world/open/<id>`, then asks UI to open that source. |
| Read document | `ui_action: "readable", document_id`, canonical title/text | Calls `QuestService.read_document`; repeated reads return its existing receipt. |
| Review writ | `ui_action: "writ", document_id: "village_writ_table"` | Records review only after MQ06 acceptance and Mara's discussion; never activates the quest or chooses an ending. |

The loot UI must re-read `WorldStateService.read_loot` and use `take_loot`/`take_crowns`. Opening grants no contents or currency. Charter access requires the solved vault puzzle; seal access requires defeated Rusk; corpse access requires that source's defeat. Offers and commits check current state. `InteractionRay` owns physical reach, visible targeting and wall occlusion. Source identity drift, inactive objects, wrong actors, stale actions and unknown IDs refuse interaction.

## Verification actually performed

Pinned Godot `4.5.2.stable.official.6ce3de25a`:

```sh
godot --headless --path . --script res://tests/run_all.gd -- \
  --suite=integration/test_world_objects.gd
```

Final result: **161 assertions, zero failed suites**, exit 0. Tests cover all thirteen art/source mappings; invalid setup and saved-record rejection; detached opened-state rendering; staged/live listener separation; repeated open and pickup; empty reconstruction; distinct candles and the ring; corpse defeat and exact once-only currency; charter/seal denial and valid access; early medicine; every readable's retained evidence/replay; first writ review from a genuine captured post-Mara snapshot; and no implicit ending.

The real player and InteractionRay prove focus through the object's own collider, wall occlusion and 2.5-meter reach. Normal player movement collides with a coffer and passes through a visible corpse purse. Repeated activation/deactivation, tree removal/re-entry and final cleanup restore all listener counts. A first fixture expected listener totals before creating the player; it was corrected to account for the player's separate subscriptions. No gameplay code was weakened to pass that fixture.

Owned files are the adapter, `tests/integration/test_world_objects.gd`, and this handoff. No world placements, content registries, shared services, root runtime or UI files were changed. Native rendered quality, final navigation around placed objects, campaign collection routes, chimes, the training dummy and audio remain their owning integration tasks; these tests do not claim a physical campaign playthrough.
