extends RefCounted
## Domain fixtures use real pickups/turn-ins; they are not a campaign playthrough.

class ArrivalBlocker extends StaticBody3D:
	var entries: int = 0
	func _enter_tree() -> void:
		entries += 1
		collision_layer = MireTypes.WORLD if entries > 1 else 0

var t: SceneTree
var game: MireGameRoot
var session: Node
var saves: Node
var bus: Node
var fail_arrival: bool = false

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	saves = t.root.get_node("SaveService")
	bus = t.root.get_node("EventBus")
	var baseline := _listeners()
	game = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(game)
	game.router.fade_seconds = 0
	game.router.world_builder = _build
	game.world_ready.connect(_activate)
	t.check((await game.start_new_game(true)).ok, "T21 reaction fixture starts the actual session/world lifecycle")
	game.player.set_physics_process(false)
	saves.set_physics_process(false)
	var fresh: Dictionary = session.snapshot()
	var reaction := _reaction()
	t.check(not reaction.shelter_lights.visible and not reaction.badge.visible, "R30 new game displays neither completed reaction")
	t.check(saves.save_slot(&"manual_1").ok, "T21 store genuine precompletion save")
	await _geometry(reaction)
	await _complete_quests(reaction)
	var completed: Dictionary = session.snapshot()
	t.check(saves.save_slot(&"manual_2").ok, "T21 store genuine completed reaction save")
	await _detached(fresh, false)
	t.check((await game.load_slot(&"manual_1")).ok, "R30 actual saved fresh state reloads")
	t.check(not _reaction().shelter_lights.visible and not _reaction().badge.visible, "R30 loading precompletion removes both reaction visuals")
	await _detached(completed, true)
	t.check((await game.load_slot(&"manual_2")).ok, "R30 actual saved completed state reloads")
	reaction = _reaction()
	t.check(reaction.shelter_lights.visible and reaction.badge.visible, "R30 completed lights and badge reconstruct from save flags")
	await _rollback()
	reaction = _reaction()
	var subscriptions := _listeners()
	reaction.deactivate()
	reaction.deactivate()
	t.check(session.restore(fresh).ok and reaction.shelter_lights.visible and reaction.badge.visible, "T21 inactive reactions ignore real session restore events")
	t.check(reaction.activate().ok and not reaction.shelter_lights.visible and not reaction.badge.visible, "T21 reactivation refreshes the currently committed session")
	t.check(reaction.activate().ok and _listeners() == subscriptions, "T21 repeated activation preserves listener cardinality")
	game.modes.push_mode(&"journal")
	t.check(t.paused and session.restore(completed).ok and reaction.shelter_lights.visible and reaction.badge.visible, "T21 actual restore event updates reactions while menus pause simulation")
	game.modes.push_mode(&"gameplay")
	var ada: NpcActor = game.router.current_world.entities[&"ada_vey"]
	reaction.free()
	t.check(not ada.model.has_node("RestoredBadge"), "T21 disposing only the helper removes its externally attached badge")
	game.free()
	saves.set_physics_process(true)
	await t.process_frame
	t.check(not t.paused and _listeners() == baseline, "T21 disposing the game removes reaction/global listeners")

func _build(world: Node3D, candidate: Dictionary) -> MireTypes.ActionResult:
	var built := game._build_world(world, candidate)
	if not built.ok: return built
	if world.scene_id == &"exterior":
		var ada: NpcActor = world.entities[&"ada_vey"]
		t.check(ada.model.has_node("RankPale") and ada.model.has_node("RestoredBadge"), "T21 production Ada retains her stripe and stages the separate returned badge")
	elif fail_arrival and world.scene_id == &"interior_inn":
		var blocker := ArrivalBlocker.new()
		blocker.position = Vector3(0, 1, 3)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(3, 2, 3)
		collider.shape = shape
		blocker.add_child(collider)
		world.add_child(blocker)
	return built

func _activate(world: Node3D) -> void:
	var reaction: SideQuestReactions = world.get_node_or_null("SideQuestReactions")
	if reaction != null:
		t.check(reaction._active, "T21 production postcommit reaction activation succeeds")

func _reaction() -> SideQuestReactions:
	return game.router.current_world.get_node("SideQuestReactions")

func _listeners() -> Array:
	return [bus.quest_updated.get_connections().size(), bus.session_restored.get_connections().size()]

func _geometry(reaction: SideQuestReactions) -> void:
	var world: Node3D = game.router.current_world
	await t.physics_frame
	t.check(reaction.candles.size() == 3 and reaction.shelter_lights.get_child_count() == 3, "R30 exactly three shelter candle meshes exist")
	t.check(reaction.find_children("*", "Light3D", true, false).is_empty(), "R41 emissive candle geometry adds no local light nodes")
	for candle: Node3D in reaction.candles:
		var flame: MeshInstance3D = candle.get_node("Flame")
		t.check(flame.material_override.emission_enabled and is_equal_approx(candle.position.y, 0.505), "T21 each authored flame emits and each candle rests on the bench top")
	var ada: NpcActor = world.entities[&"ada_vey"]
	t.check(reaction.badge.get_parent() == ada.model and reaction.badge.get_meta("item_id") == &"ada_badge" and reaction.badge.position.z < -0.19, "R30 returned badge follows Ada's model in front of her surcoat")
	for at: Vector3 in [Vector3(195, 0, -82), Vector3(197, 0, -80.3), Vector3(44, 0, -225.3), Vector3(199.5, 0, -82.8)]:
		t.check(game.router.validate_anchor(world, Transform3D(Basis.IDENTITY, at)).ok, "T21 shelter rest, Elian, Ada and memorial approaches stay clear: " + str(at))
	for id: StringName in world.rest_anchors:
		t.check(game.router.validate_anchor(world, world.rest_anchors[id]).ok, "T21 all canonical rest anchors remain clear")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = reaction.memorial.get_child(1).shape
	query.transform = Transform3D(Basis.IDENTITY, reaction.memorial.global_position + Vector3.UP * 0.2525)
	query.collision_mask = MireTypes.WORLD | MireTypes.NEUTRAL | MireTypes.HOSTILE
	query.exclude = [reaction.memorial.get_rid()]
	query.margin = 0.0
	t.check(world.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "T21 memorial geometry does not overlap another world body")
	var floor_hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(reaction.memorial.position + Vector3.UP * 0.3, reaction.memorial.position - Vector3.UP * 0.3, MireTypes.WORLD, [reaction.memorial.get_rid()]))
	t.check(not floor_hit.is_empty() and absf(floor_hit.position.y - reaction.memorial.position.y) < 0.01, "T21 memorial trestles meet the actual shelter ground")
	var duplicate := SideQuestReactions.new()
	world.add_child(duplicate)
	t.check(not duplicate.configure(world, session.snapshot()).ok and reaction.badge.get_parent() == ada.model, "T21 a duplicate helper cannot create another badge or bench")
	duplicate.free()
	t.check(not reaction.configure(world, session.snapshot()).ok, "T21 repeated configure refuses without duplicating geometry")

func _complete_quests(reaction: SideQuestReactions) -> void:
	game.modes.push_mode(&"journal")
	t.check(t.paused, "T21 side-effect event fixture runs while gameplay is paused")
	t.check(session.quests.activate(SideQuestReactions.LIGHTS_QUEST).ok, "R30 accept Three Small Lights through the real quest service")
	for index: int in range(1, 4):
		var source := StringName("monastery_candle_0" + str(index))
		t.check(session.world_state.take_loot(source, &"votive_candle", 1, StringName("t21/candle/" + str(index))).ok, "R30 real distinct candle pickup " + str(index))
		t.check(not reaction.shelter_lights.visible, "R30 pickup alone cannot prematurely light the shelter")
	var before: Dictionary = session.snapshot()
	t.check(not session.world_state.take_loot(&"monastery_candle_01", &"votive_candle", 1, &"t21/candle/duplicate").ok and session.snapshot() == before, "R30 duplicate source cannot satisfy a fourth candle or pay a reward")
	t.check(session.quests.complete(SideQuestReactions.LIGHTS_QUEST, &"t21/complete_lights").ok, "R30 legitimate candle turn-in commits")
	t.check(session.state.flags.shelter_lights and reaction.shelter_lights.visible and reaction.candles.all(func(candle: Node3D) -> bool: return candle.is_visible_in_tree()), "R30 committed turn-in immediately reveals all three candles while paused")
	t.check(not reaction.badge.visible, "T21 candle completion does not grant Ada's reaction")
	t.check(session.world_state.take_loot(&"watchtower_badge_locker", &"ada_badge", 1, &"t21/early_badge").ok, "R33 badge pickup occurs before its quest activation")
	t.check(not reaction.badge.visible and session.quests.activate(SideQuestReactions.BADGE_QUEST).ok, "R33 early badge stays unworn until accepted and returned")
	t.check(session.quests.complete(SideQuestReactions.BADGE_QUEST, &"t21/complete_badge").ok and reaction.badge.visible, "R30 genuine badge turn-in immediately attaches the visible restored badge")
	t.check(session.state.player.crowns == 47 and not session.state.key_items.has("ada_badge") and not session.state.key_items.has("votive_candle"), "R34 exact 15+20 crowns and source consumption come only from domain transactions")
	before = session.snapshot()
	var badge_id: int = reaction.badge.get_instance_id()
	for duplicate: int in 3:
		bus.quest_updated.emit(SideQuestReactions.LIGHTS_QUEST)
		bus.quest_updated.emit(SideQuestReactions.BADGE_QUEST)
		bus.session_restored.emit()
		reaction.refresh()
	t.check(session.snapshot() == before and reaction.badge.get_instance_id() == badge_id and reaction.shelter_lights.get_child_count() == 3, "R34 duplicate aftercommit events reuse meshes and change no state/rewards")
	t.check(session.quests.complete(SideQuestReactions.BADGE_QUEST, &"t21/repeat_badge").ok and session.snapshot() == before, "R34 repeated turn-in cannot duplicate the badge or reward")
	game.modes.push_mode(&"gameplay")
	await t.process_frame

func _detached(candidate: Dictionary, expected: bool) -> void:
	# Finish the live world's arrival/discovery callbacks before isolating preparation.
	await t.physics_frame
	await t.physics_frame
	await t.process_frame
	var before: Dictionary = session.snapshot()
	var subscriptions := _listeners()
	var prepared: MireTypes.ActionResult = await game.router.prepare_restore(candidate)
	t.check(prepared.ok, "T21 opposite completed state can prepare detached geometry")
	if not prepared.ok: return
	var token := StringName(prepared.payload.prepared_token)
	var world: Node3D = game.router._prepared[token].world
	var reaction: SideQuestReactions = world.get_node("SideQuestReactions")
	t.check(reaction.shelter_lights.visible == expected and reaction.badge.visible == expected, "T21 staged visuals use candidate flags rather than live session flags")
	bus.quest_updated.emit(SideQuestReactions.LIGHTS_QUEST)
	bus.quest_updated.emit(SideQuestReactions.BADGE_QUEST)
	bus.session_restored.emit()
	t.check(reaction.shelter_lights.visible == expected and reaction.badge.visible == expected, "T21 staged geometry ignores live notifications")
	t.check(_listeners() == subscriptions, "T21 staged reactions add no live listeners")
	t.check(session.snapshot() == before, "T21 staged reaction preparation has no domain effects")
	game.router.discard_prepared(token)
	t.check(_listeners() == subscriptions, "T21 discarded reaction preparation leaks no live listeners")

func _rollback() -> void:
	var world: Node3D = game.router.current_world
	var reaction := _reaction()
	var before: Dictionary = session.snapshot()
	var subscriptions := _listeners()
	var badge_id: int = reaction.badge.get_instance_id()
	fail_arrival = true
	t.check(game.router.travel(&"interior_inn", &"entry").ok, "T21 rollback fixture reaches late arrival validation")
	var arrived: Array = await game.router.travel_completed
	t.check(not arrived[1].ok and game.router.current_world == world and session.snapshot() == before, "T21 failed arrival restores the same completed world/session")
	t.check(reaction.badge.get_instance_id() == badge_id and reaction.badge.visible and reaction.shelter_lights.visible and _listeners() == subscriptions, "T21 rollback reconnects reactions exactly once and preserves their attached geometry")
	fail_arrival = false
	await t.process_frame
