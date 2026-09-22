# Frozen module contracts

See design.md D10 for public method signatures. Registries use JSON arrays with stable string IDs; getters return MireTypes definition objects. Runtime session data contains only JSON-safe values.

## State layout

`player`: health, stamina, crowns, scene_id, position [x,y,z], yaw, rest_anchor. `inventory`: array of {stack_id,item_id,quantity}. `equipment`: weapon/shield/armor stack IDs. `key_items`: item counts. `evidence`: acquisition/read/conversation IDs mapped to true. `quests`: quest IDs mapped to {state,objectives}. `world`: persistent entity ID mapped to a dictionary. `choices`: wren_terms, medicine_recipient, ending. `discoveries`: landmark IDs. `transactions`: completed receipts. `pending_delivery`: IDs mapped to {item_id,quantity}. `shop_stock`: shop IDs mapped to item counts. `flags`: puzzle_solved, free_inn, shelter_lights, restored_badge, undercroft_open. `next_stack`: monotonic stack counter.

Transactions.run(transaction_id, stage) duplicates state, calls stage(candidate), validates and commits on success. Stage returns MireTypes.ActionResult. Empty IDs fail. Failed actions never create receipts. Successful replay returns the original payload plus replayed=true. Notifications are queued in ActionResult.events as dictionaries {name,args}, emitted after commit, never on replay. Events are not saved in receipts.

Services extend RefCounted, receive GameSession via `_init(owner: Node)`, and access owner.state and owner.transactions. GameSession holds inventory, economy, quests, dialogue, world_state, and recovery typed service references as they are integrated. Root owns autoload wiring. Services must not mutate the current state outside Transactions.

## Collision

Layer bits: world=1, player=2, hostile_bodies=4, neutral_bodies=8, interactables=16, hurtboxes=32, triggers=64. Player body mask=13. Hostile body mask=3. Interaction ray mask=17. Player attack sweep mask=32, occlusion ray mask=1. Neutrals have no hostile hurtbox. Hurtboxes expose their owning combat actor.

## Runtime ownership

GameRoot owns Player, WorldContainer, WorldRouter, GameModeController, UI. The player persists through scene travel. World scene registry and persisted state apply before navigation synchronization, placement, and input release. Modal pausing affects physics, AI, attack and heal timers. Input suppression persists until every attack/interact button is released.

## Art API (T03 implements)

`VisualFactory.actor(archetype: StringName) -> Node3D`, `gear(item_id: StringName) -> Node3D`, `building(family: StringName) -> Node3D`, `prop(kind: StringName) -> Node3D`. Visual roots contain no gameplay collision or state. Actor roots expose named pivots (Head, LeftArm, RightArm, LeftLeg, RightLeg) for rigid animation. Scale uses meters, forward is -Z. Shared materials use D08 palette. All visible models are assembled final-form low-poly art, never debugging capsules.

## Foundation integration

T02 initial import, registry validation, and 11 transaction/state assertions passed with Godot 4.5.2.stable. Quest/dialogue IDs are reserved with `foundation_only`; release validation rejects these until T12/T13 replace them. No story implementation is implied by reserved IDs. `ContentValidation.validate(ContentDB, true)` is the release mode; `--release` enables it in the command-line validator.

GameSession runtime flags: `danger`, `action_locked`, `travelling`, `active`. `can_save()` additionally checks the transaction lock. Physics resource changes belong to combat/recovery services; economic/story/world changes use Transactions. Unit suites extend RefCounted, implement `run(t: SceneTree)`, and use `t.check(bool, description)`. The runner discovers `.gd` suites in tests/unit and tests/integration. Tests must not use production save paths.

Settings belong to SaveService separately from SessionState. `SaveService.settings` starts from `DEFAULT_SETTINGS`: mouse_sensitivity (radians/pixel), invert_y, fov (vertical degrees), view_bob (meters), camera_shake (bool), text_scale (1/1.25/1.5), render_mode (retro/native), shadows (low/high/off), fullscreen, vsync, five `<bus>_volume` linear values, bindings, dismissed_hints. T14 implements validated persistence; T04/T23/T24 read these fixed fields. A new game must not reset them.

`CombatMath.in_guard_cone(forward, to_attacker)` ignores vertical pitch. `CombatMath.resolve(raw_damage, armor, stamina, frontal_guard, shield_multiplier=1, perfect_parry=false, heavy_against_enemy_guard=false)` returns DamageResult without mutation. The combat component owns valid parry timing/cooldown and passes an already-multiplied raw damage value. The final parameter applies only when the victim is an enemy with ordinary guard. Guard break sets defender stamina to zero; parry stagger applies to attacker, guard-break stagger to defender.

## Player and combat attachment

MirePlayer exposes camera/head/gear, PlayerInput controls, PlayerVitals vitals, input_enabled, guarding, and a runtime combat Node reference. spawn_at(position,yaw), set_input_enabled, clear_input_edges, apply_settings, and apply_look are implemented. PlayerVitals is the sole player stamina regeneration loop. Controls.pressed/held prevent fresh actions until buttons release after mode/focus changes.

T06 approved API: CombatComponent is a player/actor child; configure_player(player, entity_id) sets player.combat; configure_enemy(actor, stable_id, EnemyDef, faction) configures transient enemy state. Methods request_attack, set_guard, receive_hit, clear_input_edges, advance, reset_combat, get_health/get_stamina, is_committed. Signals phase_changed, hit_received(request,result), hit_landed(victim_id,result), died(entity_id), staggered(seconds), feedback(outcome). CombatHurtbox owns a combat_owner reference on layer32. Persistent enemy defeat/loot is applied by a world adapter after died, not inside combat. Boss profiles use set_attack_profile(kind,profile).

## Interaction and mode integration

GameModeController.configure(player,modal_host), push_mode(mode), and pop_mode own pause/cursor/focus. Local mode_changed mirrors EventBus. InteractionRay.configure(player,controller) exposes focused/offer, refresh_focus, interact_focused and focus_changed/interaction_completed signals. InteractionComponent is an Area3D with stable entity/action IDs, focus_offset on its visible surface, physical_body exclusion for its own collider, and offer_handler(actor_id)/action_handler(actor_id,action_id). Commit rechecks spatial focus and availability. Bound handlers still use domain transactions. ModalHost.register_panel(mode,panel,first_focus) installs a real panel; controller config connects Back. See handoffs/T05.md for stack and ownership rules.

Combat is attached as Player/Combat, with Player/Hurtbox at Y0.9. Player initialization configures both once; fixtures reuse them. spawn_at resets transient combat for deliberate reconstruction; modal close never resets it. Enemy component alone regenerates guard stamina (40 maximum,10/s outside guard). Hit receipt emits synchronously at physics priority-20; healing must commit afterward and cancel on actual health loss. Additional APIs apply_stagger, reset_combat, input_driven and enemy-only health/max_health/guard_stamina are documented in handoffs/T06.md.

T08 is integrated as GameSession.inventory and GameSession.world_state. ContentDB.containers holds validated immutable definitions. InventoryService.find_stack returns a detached stack; stage_add/stage_reward/stage_remove/stage_remove_key support atomic compound transactions. Keys use evidence[item_id] and evidence["pickup/<entity_id>"]; rewards use evidence["reward/<delivery_id>"]. Every key pickup has its own entity and quantity1, including three separate candles. World records use kind container/corpse, opened, remaining items, crowns_remaining and corpse defeated/disabled/archetype; saved quantities cannot exceed the authored source. See handoffs/T08.md for complete APIs. Timed consumption binds consume_handler in T09.

Automatic enemy RETURN uses reset_combat(false) so prior hit sequences remain rejected, including the five-second return heal. Explicit load/rest/reconstruction may clear history. Applying unchanged live world flags must preserve attack phase, elapsed time and reservation. EncounterCoordinator.is_dangerous performs a current engagement/15m LOS check for recovery commits.

T09 services are being integrated as GameSession.economy/recovery. Economy prices/views return ActionResult payloads (unit_price/items). Recovery binds (player, danger_provider()->bool, reset_encounters()->ActionResult, travel_handler(anchor_id,reason,apply)->ActionResult); apply=false is read-only preflight. Pending travel returns pending=true plus a unique operation_id and holds GameSession.travelling; WorldRouter must call finish_pending_travel(operation_id,result) after clearing travelling with an actual terminal result. Flag clearing alone is not success. Recovery owns its committed receipt and retries placement without another fee. GameSession ticks recovery at priority20; recovery freezes healing explicitly while paused. Inventory.consume_handler binds start_consume. Recovery changes the snapshot scene/anchor at commit, so WorldRouter must track its actual loaded scene independently of that snapshot field.

T10/T11 world scenes expose scene_id, entrances and rest_anchors dictionaries of Transform3D values, entities of Node references, navigation_regions, navigation_synchronized, and is_navigation_ready(). These runtime references are never serialized. Navigation readiness checks the relevant region iteration and closest-point owner as well as the map iteration.

T12 is integrated as GameSession.quests. Inventory/evidence/defeat notifications reconcile objective progress after commit. Quest completion and choices use canonical receipts; rewards and world consequences commit together. QuestPredicates.validate_snapshot follows structural validation at the persistence boundary. Journal/tracking/document/epilogue view methods return detached presentation data. Exterior objectives in other scenes expose their canonical portal_id as the exterior hint target. See handoffs/T12.md for all story step and source IDs.

T13 is integrated as GameSession.dialogue. Dialogue view node_id is speaker-qualified; pass it unchanged to choose. Routed shop/rest/challenge results carry command_pending=true for runtime execution. Staged NpcActor.configure(session,id,false) creates geometry without live listeners; activate() runs after world activation and deactivate() runs on tree exit. Activation is idempotent, including a travel rollback. See handoffs/T13.md.

WorldRouter failed-arrival rollback restores GameModeController.snapshot_stack() through restore_stack(saved), then uses the normal world_activated hook to reactivate restored live entities. The hook must be idempotent and must not create duplicate content. Detached construction belongs in world_builder(world,snapshot), before collision/navigation validation.

GameSession.fresh_snapshot() returns the complete detached initial session without touching active state, dialogue, recovery, settings or events. New Game uses this builder, and T14 prepares the destination from it before replacing live state.

MireGameRoot composes one Player and WorldContainer in its own SubViewport. A nearest-filtered TextureRect displays 540-high Retro or window-resolution Native output; the native Interface/ModalHost sits outside it. The expanded canvas preserves window aspect and only letterboxes outside4:3–21:9. Unhandled gameplay mouse motion forwards into the 3D viewport; player look uses screen_relative so output scaling cannot change sensitivity. Root owns apply_settings, action_result and world_ready hooks. Save/UI integration consumes these objects without creating another player or mode controller.

T14 SaveService binds once to the active player/router. save_slot is synchronous; load_slot and start_new_game are awaited through MireGameRoot. Slots are autosave/manual_1/manual_2/manual_3; inspect_slot and list_slots are read-only, and use_backup=true requires explicit recovery selection. continue_slot selects a valid primary by timestamp. Queued autosave results emit autosave_finished(reason,result); ending_ready gates epilogue, with retry_autosave or explicit continue_without_saving after failure. settings_changed updates root rendering and the camera; save_settings/rebind preserve settings independently. leave_to_title first calls accepted SaveService.leave_session, then clears the world and retains one disabled player.

TrainingDummy is a stationary, nonrewarding straw target activated with the world. Its attackable body uses the hostile-body layer so world occlusion does not block its own hurtbox. It creates no persistent world record or defeat and never attacks. Interact returns ui_action=training,step=intro for UI instructions; actual hits use the shared combat resolver and rebound the straw body.

WorldObject.configure(source_id,kind,snapshot) creates inactive fixed loot/readable geometry from the detached candidate. activate/deactivate manage live subscriptions after world commit. apply_persistent_state renders only its record. Loot emits ui_action=loot with entity_id; readables emit readable with document_id; valid final writ review emits writ. Actor/purse pairs share the canonical spawn ID, with the actor retaining world.entities ownership. See handoffs/T08-world-objects.md.

CampaignWorld(player) supplies router.world_builder through build(world,candidate). Root calls activate(world) after the generic NPC/object/training activation. Scene-owned population hooks connect enemy defeat and danger only while active; actor IDs remain the world registry owners and sibling purses share those canonical loot sources. The opening currently populates three speakers, the cart encounter, sign and training station. T17 adds later content after the opening acceptance gate.
