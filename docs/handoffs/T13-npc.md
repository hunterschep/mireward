# T13 NPC adapter

Status: IMPLEMENTED; focused headless behavior verified. World placement and visual acceptance remain integration work.
Repository checkpoint: owned working-tree files; integration owner commits them together.

## Delivered

`scripts/dialogue/npc_actor.gd` and `scenes/actors/npc.tscn` provide the seven stationary, invulnerable civilian speakers. They use their existing `VisualFactory.actor` art and `VisualFactory.pose` idle animation. The current toolkit has no separate ArtAnimator class. Civilians have neutral physical bodies, no combat component and no hurtbox. Unknown IDs and `captain_rusk` are rejected without leaving an invisible body obstacle.

Each actor exposes `npc_id`, `entity_id`, `interaction`, `model`, `name_label`, and `quest_marker`. `configure(session: Node, speaker_id: StringName, live: bool = true) -> MireTypes.ActionResult` runs after tree attachment. An omitted entity ID defaults to the canonical NPC ID. Repeating the same configuration refreshes presentation without duplicating nodes; changing a configured identity is refused. Authored scene exports automatically configure against GameSession in `_ready`, using the exported `activate_on_ready` setting, which defaults to true for fixtures.

World preparation must call `configure(session, npc_id, false)`. This builds geometry and an initial name/marker view without EventBus subscriptions, idle processing or enabled interaction. When preparing an actor with an already exported `npc_id`, set `activate_on_ready = false` before tree attachment. `activate() -> MireTypes.ActionResult` binds the three session events once, refreshes presentation and enables idle/interaction. `deactivate() -> void` disconnects those listeners and disables idle/interaction. Both are repeatable. Tree exit deactivates automatically; tree re-entry preserves geometry and requires explicit activation by the world owner.

The session provides `dialogue.npc_view(npc_id)` with `npc_id`, `speaker_name`, and marker `turn_in`, `quest`, or `none`. The actor displays the returned name and respectively `?`, `!`, or no marker. Quest, choice and session-restored events refresh presentation; `refresh_view()` is also public. Missing service/view disables interaction. No state or rewards are changed by this adapter.

Interaction uses stable entity ID and action `talk`, explicitly excludes its own physical body from visibility tests, and returns the exact `dialogue.start(npc_id)` ActionResult. The integration UI consumes that result to open dialogue. The adapter does not open a modal or substitute a successful result for a failed conversation.

## Verification actually performed

Pinned engine: Godot `4.5.2.stable.official.6ce3de25a`.

```sh
godot --headless --path . --script res://tests/run_all.gd -- --suite=/tmp/mireward-t13-npc.gd
godot --headless --path . --script res://tests/run_all.gd -- --suite=/tmp/mireward-t13-npc-lifecycle.gd
```

PASS: 37 assertions, zero failed suites. The temporary RefCounted probe uses the normal isolated runner and a narrow fake dialogue service. It covers every civilian model, captain/unknown-ID refusal, collision masks and absent combat nodes, stable identity, real ActionResult identity and refusal propagation, stale actions, marker changes through EventBus, unavailable views/services, repeat configuration, exported identity configuration, idle station preservation, pause, and listener-count restoration after freeing actors. It also instantiates the real player, mode controller and InteractionRay: the NPC is focusable, a world wall blocks it, and distance beyond 2.5 meters refuses focus.

PASS: 19 lifecycle assertions, zero failed suites. The separate probe counts all three event subscriptions and dialogue view reads to prove staged/deactivated actors ignore live events. It checks disabled interaction/idle, repeat activation/deactivation, re-entry without duplicate geometry or listeners, explicit reactivation, staged reconfiguration, free cleanup and authored exports with `activate_on_ready = false`. The 37-assertion adapter probe was rerun after the lifecycle change and still passes.

## Integration and remaining checks

Instantiate the scene, set its entity ID and parent-owned position/yaw, add it to the prepared world, then call `configure(session, npc_id, false)`. Call `activate()` only when that world becomes active, and `deactivate()` when it ceases to be active. Register the actor or its interaction in the world entity registry according to the world owner's convention. NPC placement, final service integration, native visual review, readability at both render modes/text scales and gameplay interaction remain UNVERIFIED by this bounded task. Both temporary probes are available for integration into the parent-owned test suite; no shared test, map, world or autoload file was edited.
