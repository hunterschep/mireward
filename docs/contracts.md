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
