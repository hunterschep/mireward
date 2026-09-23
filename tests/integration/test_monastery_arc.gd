extends RefCounted
## Isolated spatial fixtures position the player; story effects use real adapters/UI.

class ArrivalBlocker extends StaticBody3D:
	var entries: int = 0
	func _enter_tree() -> void:
		entries += 1
		collision_layer = MireTypes.WORLD if entries > 1 else 0

const MQ01 := &"mq_01_bread_and_iron"
const MQ02 := &"mq_02_the_kings_due"
const MQ03 := &"mq_03_a_bell_without_rope"
var t: SceneTree
var game: MireGameRoot
var session: Node
var saves: Node
var crypt: CryptContent

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	saves = t.root.get_node("SaveService")
	var original: Dictionary = saves.settings.duplicate(true)
	var original_size: Vector2i = t.root.size
	t.root.size = Vector2i(1280, 720)
	game = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(game)
	game.router.fade_seconds = 0
	crypt = game.crypt
	game.world_ready.connect(_activate)
	await _detached()
	var started: MireTypes.ActionResult = await game.start_new_game(true)
	t.check(started.ok, "T18 normal monastery fixture starts the actual production world")
	await _complete_first_two()
	await _request_charter()
	t.check(session.state.quests[String(MQ03)].state == "ACTIVE", "R29 Elian's initial request alone does not attest the charter")
	await _enter_crypt()
	_check_population()
	await _keeper_approach()
	_clear_keepers()
	await _puzzle_and_reload()
	await _take_charter()
	t.check(session.state.quests[String(MQ03)].state == "READY", "R29 solved crypt and acquired charter make Elian return available")
	await _exit_crypt()
	await _attest()
	t.check(session.state.player.crowns == 80, "R29 MQ01-MQ03 physical handoffs grant exact 18+22+28 crowns")
	await _safe_exterior()
	started = await game.start_new_game(true)
	t.check(started.ok, "R33 early-explorer fixture starts a genuinely fresh campaign")
	if not started.ok:
		printerr(started.message_key)
	await _enter_crypt()
	_clear_keepers()
	await _ring(&"reed")
	await _ring(&"stone")
	await _ring(&"flame")
	await _take_charter()
	t.check(session.state.quests[String(MQ03)].state == "LOCKED" and session.state.key_items.orra_charter == 1 and session.state.flags.puzzle_solved, "R33 early physical crypt solution and charter persist before quest acceptance")
	await _exit_crypt()
	await _interact(&"sister_elian")
	t.check(not session.state.evidence.get("conversation/" + String(MQ03) + "/request_charter", false) and not session.state.evidence.get("conversation/" + String(MQ03) + "/attest_charter", false), "R33 meeting Elian early credits neither her later request nor attestation")
	_escape()
	await _frames(3)
	await _complete_first_two()
	await _request_charter()
	t.check(session.state.quests[String(MQ03)].state == "READY", "R33 early charter/puzzle reconcile after the separate active Elian request")
	await _attest()
	t.check(session.state.player.crowns == 80 and session.state.key_items.toll_receipt == 1 and session.state.key_items.orra_charter == 1, "R29 early route pays the same totals and retains both main documents")
	await _safe_exterior()
	var final_slot: MireTypes.ActionResult = saves.save_slot(&"manual_3")
	t.check(final_slot.ok and saves.inspect_slot(&"manual_3").payload.snapshot.quests[String(MQ03)].state == "COMPLETED", "R37 post-MQ03 fixture writes and validates an actual save")
	game.free()
	await t.process_frame
	saves.save_settings(original)
	t.root.size = original_size
	t.check(not t.paused and session.recovery.player == null, "T18 crypt test removes runtime/puzzle subscriptions with the game")

func _build(world: Node3D, candidate: Dictionary) -> MireTypes.ActionResult:
	return game._build_world(world, candidate)

func _activate(world: Node3D) -> void:
	if world.scene_id == &"interior_crypt":
		var puzzle: CryptContent.Puzzle = world.entities[CryptContent.PUZZLE_ID]
		t.check(puzzle._active and puzzle.interactions[&"reed"].enabled, "T18 production root activates the committed crypt puzzle")

func _detached() -> void:
	var before: Dictionary = session.snapshot()
	var candidate: Dictionary = before.duplicate(true)
	candidate.player.scene_id = "interior_crypt"
	candidate.player.position = [0.0, 0.0, 3.0]
	var bus: Node = t.root.get_node("EventBus")
	var listeners := [bus.evidence_acquired.get_connections().size(), bus.session_restored.get_connections().size(), game.player.combat.phase_changed.get_connections().size()]
	var prepared: MireTypes.ActionResult = await game.router.prepare_restore(candidate)
	t.check(prepared.ok, "R31 crypt prepares early without a quest prerequisite")
	if not prepared.ok:
		printerr(prepared.message_key)
		return
	var token := StringName(prepared.payload.prepared_token)
	var world: Node3D = game.router._prepared[token].world
	var puzzle: CryptContent.Puzzle = world.entities[CryptContent.PUZZLE_ID]
	t.check(not crypt.build(world, candidate).ok, "R04 duplicate crypt construction refuses existing identities")
	t.check(session.snapshot() == before and listeners == [bus.evidence_acquired.get_connections().size(), bus.session_restored.get_connections().size(), game.player.combat.phase_changed.get_connections().size()], "R39 prepared crypt adds no live mutations or subscriptions")
	t.check(puzzle.gate.collision_layer == MireTypes.WORLD and not puzzle.interactions[&"reed"].enabled, "R31 prepared gate is closed and chimes cannot interact")
	var population: CampaignWorld.Population = world.get_node("CampaignPopulation")
	t.check(population.enemies.size() == 4 and population.coordinator.player == null, "R18 four prepared keepers share one unbound coordinator")
	game.router.discard_prepared(token)
	t.check(session.snapshot() == before, "R39 discarded crypt leaves live progress intact")

func _complete_first_two() -> void:
	await _interact(&"mara_venn")
	await _click("dialogue/accept_mq01")
	await _click("dialogue/@leave")
	await _interact(&"cart_coffer")
	await _click("take/cart_medicine")
	_escape()
	await _frames(3)
	await _interact(&"mara_venn")
	await _click("dialogue/complete_mq01")
	await _click("dialogue/@leave")
	await _interact(&"mara_venn")
	await _click("dialogue/accept_mq02")
	await _click("dialogue/@leave")
	var before: int = session.state.player.crowns
	await _interact(&"toll_notice")
	t.check(_visible_text(game.ui.panels[&"readable"]).contains("grain levy doubled"), "R29 physical checkpoint notice shows canonical retained evidence")
	_escape()
	await _frames(3)
	await _interact(&"checkpoint_receipt_box")
	await _click("take/toll_receipt")
	_escape()
	await _frames(3)
	for id: String in ["road_checkpoint_levy_spearman_01", "road_checkpoint_levy_spearman_02", "road_checkpoint_levy_spearman_03"]:
		t.check(not session.state.world.get(id, {}).get("defeated", false), "R29 checkpoint evidence requires no soldier defeat or toll: " + id)
	t.check(session.state.player.crowns == before, "R29 both checkpoint evidence interactions cost no money")
	await _interact(&"mara_venn")
	await _click("dialogue/complete_mq02")
	t.check(session.state.quests[String(MQ02)].state == "COMPLETED" and session.state.player.crowns == before + 22 and session.state.key_items.toll_receipt == 1, "R29 Mara's actual MQ02 turn-in pays 22 and retains the receipt")
	await _click("dialogue/@leave")

func _request_charter() -> void:
	await _interact(&"sister_elian")
	await _click("dialogue/accept_mq03")
	await _click("dialogue/@leave")
	await _interact(&"sister_elian")
	t.check(_visible_text(game.ui.panels[&"dialogue"]).contains("reed, stone, flame"), "R31 Elian states the full solution in text")
	await _click("dialogue/record_request_charter")
	t.check(session.state.evidence.get("conversation/" + String(MQ03) + "/request_charter", false) and not session.state.evidence.get("conversation/" + String(MQ03) + "/attest_charter", false), "R29 Elian's initial request and final attestation have distinct evidence")
	await _click("dialogue/@leave")

func _enter_crypt() -> void:
	await _interact(&"crypt_door")
	await _wait_scene(&"interior_crypt")

func _exit_crypt() -> void:
	await _interact(&"crypt_exit")
	await _wait_scene(&"exterior")

func _check_population() -> void:
	var world: Node3D = game.router.current_world
	var population: CampaignWorld.Population = world.get_node("CampaignPopulation")
	t.check(population.enemies.size() == 4 and population.coordinator.actors().size() == 4, "R18 committed crypt has exactly four shared-AI keepers")
	for actor: EnemyActor in population.enemies:
		t.check(String(actor.entity_id).begins_with("crypt_hollow_keeper_") and actor.definition.id == &"hollow_keeper" and actor.player == game.player, "R18 crypt actors keep their distinct canonical identities and live player binding")
	t.check(not world.entities.has(&"monastery_yard_hollow_keeper_01") and not world.entities.has(&"monastery_yard_hollow_keeper_02"), "R18 exterior monastery keepers cannot duplicate inside crypt")
	var puzzle: CryptContent.Puzzle = world.entities[CryptContent.PUZZLE_ID]
	var listeners: int = t.root.get_node("EventBus").evidence_acquired.get_connections().size()
	t.check(crypt.activate(world).ok and t.root.get_node("EventBus").evidence_acquired.get_connections().size() == listeners, "R39 repeated puzzle activation does not multiply listeners")
	for label: Label3D in puzzle.labels:
		t.check(label.visible and label.text in ["Reed", "Stone", "Flame"], "R31 each chime has a visible text label independent of color/audio")

func _clear_keepers() -> void:
	# Damage injection isolates the puzzle/save tests; it is not combat-play evidence.
	game.modes.push_mode(&"gameplay")
	var crowns: int = session.state.player.crowns
	var population: CampaignWorld.Population = game.router.current_world.get_node("CampaignPopulation")
	for actor: EnemyActor in population.enemies:
		if actor.combat.dead: continue
		var result := actor.combat.receive_hit(MireTypes.DamageRequest.new(&"monastery_fixture", 1, actor.entity_id, 100, &"heavy", game.player.global_position, &"player"))
		t.check(result.outcome == &"killed" and session.state.world[String(actor.entity_id)].defeated, "R18 real keeper death commits once through shared population hooks")
		t.check(population.purses[actor.entity_id].collision_layer == 0 and not population.purses[actor.entity_id].interaction.enabled, "R25 zero-crown keeper cannot expose a blocking or rewarding purse")
	t.check(session.state.player.crowns == crowns, "R25 crypt keepers add no unearned currency")

func _puzzle_and_reload() -> void:
	var muted: Dictionary = saves.settings.duplicate(true)
	for key: String in ["master_volume", "ambience_volume", "effects_volume", "ui_volume", "music_volume"]:
		muted[key] = 0.0
	t.check(saves.save_settings(muted).ok, "R46 muted-audio crypt test uses actual persisted sound settings")
	await _interact(&"abbey_inscription")
	var clue: String = _visible_text(game.ui.panels[&"readable"])
	t.check(clue.contains("Reed for the traveler") and clue.contains("Stone for the shelter") and clue.contains("Flame for the watch"), "R31 adjacent readable supplies the complete text-only clue")
	_escape()
	await _frames(3)
	var coffer: WorldObject = game.router.current_world.entities[&"charter_vault_coffer"]
	t.check(not coffer.interaction.get_offer(&"player").allowed and not session.state.evidence.get("orra_charter", false), "R31 closed vault also refuses premature charter access")
	await _gate_walk(false)
	var health: float = session.state.player.health
	var crowns: int = session.state.player.crowns
	var receipts: int = session.state.transactions.size()
	await _ring(&"stone")
	var puzzle := _puzzle()
	t.check(session.quests.puzzle_progress == 0 and puzzle.status.text.contains("Wrong order") and session.state.player.health == health and session.state.player.crowns == crowns and session.state.transactions.size() == receipts, "R31 wrong order resets with readable feedback and no damage/currency/receipt penalty")
	await _ring(&"reed")
	t.check(session.quests.puzzle_progress == 1 and puzzle.markers[0].visible and puzzle.labels[0].text.contains("Set") and not puzzle.markers[1].visible, "R31 first correct activation visibly lights exactly one marked chime")
	await _ring(&"reed")
	t.check(session.quests.puzzle_progress == 0 and not puzzle.markers[0].visible, "R31 repeating reed cannot inflate progress and resets its marker")
	await _ring(&"reed")
	await _ring(&"stone")
	t.check(session.quests.puzzle_progress == 2 and not session.state.flags.puzzle_solved, "R31 two correct chimes remain unsolved")
	await _rollback_partial()
	await _save_reload(&"manual_1")
	puzzle = _puzzle()
	t.check(session.quests.puzzle_progress == 0 and not session.state.flags.puzzle_solved and puzzle.gate.collision_layer == MireTypes.WORLD and not puzzle.markers[0].visible, "R31 real partial-progress save/load resets to zero with the gate closed")
	await _ring(&"reed")
	await _ring(&"stone")
	await _ring(&"flame")
	puzzle = _puzzle()
	t.check(session.state.flags.puzzle_solved and puzzle.gate.collision_layer == 0 and puzzle.markers[0].visible and puzzle.markers[1].visible and puzzle.markers[2].visible, "R31 third correct chime permanently opens collision and lights all three markers")
	t.check(not session.state.evidence.get("orra_charter", false), "R33 solving and charter collection remain separate saved facts")
	await _gate_walk(true)
	await _save_reload(&"manual_2")
	puzzle = _puzzle()
	t.check(session.state.flags.puzzle_solved and puzzle.gate.collision_layer == 0 and puzzle.status.text.contains("open"), "R31 solved vault reconstructs open from the durable flag")
	t.check(not puzzle.interactions[&"reed"].get_offer(&"player").allowed, "R31 solved chimes cannot replay completion through a stale interaction")

func _save_reload(slot: StringName) -> void:
	game.player.spawn_at(Vector3(0, 0, 3))
	await _frames(4)
	var count: int = t.root.get_node("EventBus").evidence_acquired.get_connections().size()
	var written: MireTypes.ActionResult = saves.save_slot(slot)
	t.check(written.ok, "R37 crypt writes a real safe snapshot: " + String(slot))
	var loaded: MireTypes.ActionResult = await game.load_slot(slot)
	t.check(loaded.ok and game.router.loaded_scene_id == &"interior_crypt", "R38 actual file load reconstructs the crypt")
	await _frames(3)
	t.check(t.root.get_node("EventBus").evidence_acquired.get_connections().size() == count, "R39 crypt reconstruction retains one puzzle listener")
	for actor: EnemyActor in game.router.current_world.get_node("CampaignPopulation").enemies:
		t.check(actor.combat.dead, "R38 defeated crypt keepers stay defeated after reload")

func _gate_walk(opened: bool) -> void:
	game.player.spawn_at(Vector3(0, 0, -34), 0)
	await _frames(2)
	Input.action_press(&"move_forward")
	await _frames(50)
	Input.action_release(&"move_forward")
	await _frames(5)
	t.check(game.player.global_position.z < -35.8 if opened else game.player.global_position.z > -34.65, "R31 actual player capsule crosses only the solved vault gate")

func _take_charter() -> void:
	await _interact(&"charter_vault_coffer")
	await _click("take/orra_charter")
	t.check(session.state.key_items.get("orra_charter", 0) == 1 and session.state.evidence.get("pickup/charter_vault_coffer", false), "R33 physical fixed vault coffer grants its canonical charter once")
	_escape()
	await _frames(3)

func _attest() -> void:
	await _interact(&"sister_elian")
	var node: StringName = StringName(session.dialogue.view().node_id)
	var crowns: int = session.state.player.crowns
	await _click("dialogue/complete_mq03")
	t.check(session.state.player.crowns == crowns + 28 and session.state.quests[String(MQ03)].state == "COMPLETED" and session.state.quests.mq_04_names_in_the_ledger.state == "AVAILABLE", "R29 actual Elian attestation pays 28 once and unlocks Wren")
	var repeated: MireTypes.ActionResult = session.dialogue.choose(node, &"complete_mq03")
	t.check(not repeated.ok and session.state.player.crowns == crowns + 28, "R34 stale repeated Elian turn-in cannot duplicate rewards")
	await _click("dialogue/@leave")

func _ring(symbol: StringName) -> void:
	await _interact(StringName("crypt_" + String(symbol) + "_chime"))

func _puzzle() -> CryptContent.Puzzle:
	return game.router.current_world.entities[CryptContent.PUZZLE_ID]

func _interact(id: StringName) -> void:
	game.modes.push_mode(&"gameplay")
	await _frames(1)
	var world: Node3D = game.router.current_world
	var target: Node3D = world.entities.get(id)
	t.check(target != null, "T18 authored physical target is present: " + String(id))
	if target == null: return
	var component: InteractionComponent = target if target is InteractionComponent else target.interaction
	var base: Vector3 = target.global_position
	base.y = 0
	var forward: Vector3 = Vector3.BACK if component.kind == "door" else -target.global_basis.z
	if id == &"crypt_exit": forward = Vector3.FORWARD
	var focused: bool = false
	for direction: Vector3 in [forward, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD]:
		var at: Vector3 = base + direction * 1.6
		if not game.router.validate_anchor(world, Transform3D(Basis.IDENTITY, at)).ok: continue
		game.player.spawn_at(at)
		game.player.camera.look_at(component.focus_position(), Vector3.UP)
		await _frames(2)
		game.interaction.refresh_focus()
		if game.interaction.focused == component:
			focused = true
			break
	t.check(focused, "R09 clear grounded approach reaches real eye-ray target: " + String(id))
	if not focused: return
	var result := game.interaction.interact_focused()
	t.check(result.ok, "R09 actual world interaction succeeds: " + String(id))
	if not result.ok: printerr(result.message_key)
	await _frames(2)

func _click(id: String) -> void:
	var button: Button
	for node: Node in game.modal_host.find_children("*", "Button", true, false):
		if node.get_meta("ui_id", "") == id and node.is_visible_in_tree():
			button = node
			break
	t.check(button != null and not button.disabled, "T18 actual UI control available: " + id)
	if button != null and not button.disabled: button.pressed.emit()
	await _frames(3)

func _wait_scene(scene_id: StringName) -> void:
	for frame: int in 240:
		if not session.travelling and game.router.loaded_scene_id == scene_id:
			break
		await t.physics_frame
	t.check(not session.travelling and game.router.loaded_scene_id == scene_id, "R06 physical portal reaches " + String(scene_id))
	await _frames(3)

func _escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func _visible_text(parent: Node) -> String:
	var text: String = ""
	for node: Node in parent.find_children("*", "Label", true, false):
		text += node.text + "\n"
	return text

func _frames(count: int) -> void:
	for frame: int in count:
		await t.physics_frame
	await t.process_frame

func _safe_exterior() -> void:
	game.player.spawn_at(Vector3(32, 0, 252))
	await _frames(20)
	t.check(not game.router.is_dangerous(), "T18 isolated save/new-game fixture retreats to a genuinely safe exterior anchor")

func _keeper_approach() -> void:
	var actor: EnemyActor = game.router.current_world.entities[&"crypt_hollow_keeper_03"]
	game.player.spawn_at(Vector3(1.35, 0, -34))
	var nearest: float = actor.global_position.distance_to(game.player.global_position)
	for frame: int in 360:
		await t.physics_frame
		nearest = minf(nearest, actor.global_position.distance_to(game.player.global_position))
		if nearest < 2.6: break
	if nearest >= 2.6:
		var actors: Array[Dictionary] = []
		for other: EnemyActor in actor.coordinator.actors():
			actors.append({"id": String(other.entity_id), "position": other.global_position, "state": String(other.state), "velocity": other.velocity, "thinking": other.thinking, "visible": other.has_player_line_of_sight(), "nav_ready": other.navigation_ready(), "target": other.navigation.target_position})
		print("CRYPT_NAV_PROBE " + JSON.stringify({"nearest": nearest, "player": game.player.global_position, "actors": actors}))
	t.check(nearest < 2.6, "R19 actual keeper navigation can approach through the chime row")

func _rollback_partial() -> void:
	game.modes.push_mode(&"pause")
	var world: Node3D = game.router.current_world
	var puzzle := _puzzle()
	var snapshot: Dictionary = session.snapshot()
	var listeners: int = t.root.get_node("EventBus").evidence_acquired.get_connections().size()
	game.router.world_builder = func(destination: Node3D, candidate: Dictionary) -> MireTypes.ActionResult:
		var built := _build(destination, candidate)
		if not built.ok: return built
		var blocker := ArrivalBlocker.new()
		blocker.position = Vector3(0, 1, 3)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(3, 2, 3)
		collision.shape = shape
		blocker.add_child(collision)
		destination.add_child(blocker)
		return built
	var requested := game.router.travel(&"interior_inn", &"entry")
	t.check(requested.ok, "R39 partial-puzzle rollback reaches a real arrival attempt")
	var finished: Array = await game.router.travel_completed
	t.check(not finished[1].ok and game.router.current_world == world and session.snapshot() == snapshot, "R39 failed arrival restores the same crypt without changing its snapshot")
	t.check(session.quests.puzzle_progress == 2 and puzzle.markers[0].visible and puzzle.markers[1].visible and puzzle.interactions[&"flame"].enabled, "R31 failed travel reactivates the original chimes without losing transient progress")
	t.check(t.root.get_node("EventBus").evidence_acquired.get_connections().size() == listeners, "R39 failed arrival reconnects exactly one puzzle listener")
	game.router.world_builder = game._build_world
	game.modes.pop_mode()
	await _frames(2)
