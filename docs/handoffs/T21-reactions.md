# T21 shelter lights and returned badge

This bounded checkpoint implements the two ready SQ04/SQ05 presentation effects. It does not claim full T21 verification, which still depends on the later campaign/side-quest integration.

## Composition API

`SideQuestReactions` is a scene-owned Node3D. After `CampaignWorld.build()` has placed the exterior NPCs, add one helper directly to the exterior and call `configure(world, detached_candidate) -> ActionResult`. Use the local node name `SideQuestReactions`. Call `activate() -> ActionResult` after world commit. Other scenes need no helper.

Construction reads only the supplied candidate's `shelter_lights` and `restored_badge` flags. It creates no live listeners and changes no session state. Activation subscribes once to the two relevant `quest_updated` IDs and `session_restored`, then refreshes from committed state. Updates work while menus pause simulation. `deactivate()` and tree exit disconnect idempotently. Rollback re-entry calls `activate()` again. No frame polling is used.

Root integrated production GameRoot composition and activation after this handoff. Its rerun passed73 assertions using the production builder directly, including rollback. The owner changed neither shared file.

## Visible effects

- **Three Small Lights:** a small original bench stands at (199.5, 0, -84.5), derived from the unchanged monastery rest anchor plus (4.5, 0, -2.5). Three original `votive_candle` models appear on its top only when `shelter_lights` is true. Their existing flame material is emissive. The helper adds **zero Light3D nodes**, preserving the four-local-light budget. The bench's physical dimensions match the visible support and stay clear of Elian, the shelter rest point and nearby approaches.
- **The Broken Badge:** one original `ada_badge` gear model attaches to Ada's model at local (0.12, 1.19, -0.205), scale 0.75, visible only when `restored_badge` is true. Her base art has a rank stripe and belt buckle but no returned-badge gear or rook emblem. Refresh only toggles visibility, so repeat events cannot duplicate the badge. The helper owns and removes the attachment when freed, while ordinary tree exit preserves it for rollback.

Public inspection handles are `shelter_lights`, `candles`, `badge` and `memorial`. These are local presentation nodes, not new persistent entity IDs. All meshes/materials come from existing VisualFactory/ArtGear assets. No map, asset generator, UI or service changes are required.

## Verification actually run

Pinned Godot `4.5.2.stable.official.6ce3de25a` import passed. The permanent focused suite passed **73 assertions**, zero failures:

```sh
/Users/hunterschep/.local/share/mireward-tools/godot-4.5.2/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/run_all.gd -- --suite=integration/test_side_reactions.gd
```

The test composes the helper into actual MireGameRoot/WorldRouter preparation and activation. It uses real SQ04/SQ05 activation, distinct WorldState pickups and QuestService turn-ins, including early badge pickup. It verifies pre/post visuals, exact currency/source consumption, duplicate pickup/turn-in/event delivery, paused updates, opposite detached snapshots, real save-file reload in both directions, failed-arrival rollback, reactivation listener counts, helper-only badge cleanup and full runtime cleanup. Actor movement and the autonomous autosave scheduler are stopped for the controlled fixture; explicit save/load calls remain real. Arrival/discovery callbacks finish before the detached-state comparison. No completed quest state is forged.

Geometry checks confirm all rest anchors, Elian/Ada/memorial approaches, bench ground contact and nonoverlap. The three emitted flame materials and absence of added local lights are checked directly.

One isolated background Compatibility/OpenGL process captured four before/after images, all in gameplay mode at 100 HP, and exited successfully. All four were visually inspected at 1280×720 with the actual 960×540 Retro world render:

- `tests/output/side_reactions/before_shelter.png` and `after_shelter.png`: empty bench becomes three distinct grounded, visibly lit candles.
- `tests/output/side_reactions/before_ada.png` and `after_ada.png`: returned badge appears on the upper chest, clear of the existing rank stripe and shield.

The ignored capture script uses the same genuine pickup/turn-in APIs, isolated saves and scripted viewpoints, with bounded draws. Its log and launch record are in that directory. No exported-app or foreground input was used. These captures verify presentation only; native campaign traversal and full T21 acceptance remain outside this checkpoint.
