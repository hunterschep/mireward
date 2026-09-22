extends RefCounted

const ObjectScript = preload("res://scripts/world/world_object.gd")
const QuestFixture = preload("res://tests/unit/test_quests.gd")
var t: SceneTree
var session: Node
var bus: Node
var arena: Node3D

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	bus = t.root.get_node("EventBus")
	session.new_game()
	arena = Node3D.new()
	t.root.add_child(arena)
	var baseline: Array[int] = _listeners()
	_catalog_and_staging()
	_open_and_loot()
	_pickups_and_corpses()
	_gates_and_readables()
	await _ray_and_lifecycle()
	arena.queue_free()
	await t.process_frame
	t.check(_listeners() == baseline, "R40 all world objects release their live subscriptions")
	session.new_game()

func _catalog_and_staging() -> void:
	for id: String in t.root.get_node("ContentDB").containers:
		var object: StaticBody3D = _object(id)
		t.check(object.entity_id == StringName(id) and object.model != null and object.interaction.physical_body == object, "R41 fixed source has visible art and stable physical identity: " + id)
		if id != "shrine_ring_bowl":
			t.check(object.model.get_meta("prop_kind") == StringName(ObjectScript.CONTAINERS[id]), "R41 fixed source selects its authored art family")
	var invalid: StaticBody3D = ObjectScript.new()
	arena.add_child(invalid)
	t.check(not invalid.configure(&"not_authored", &"loot", session.snapshot()).ok and invalid.model == null and invalid.collision_layer == 0, "R04 unknown loot cannot produce blank art or collision")
	t.check(not invalid.configure(&"cart_coffer", &"door", session.snapshot()).ok, "R04 unknown object kind is rejected")
	t.check(not invalid.configure(&"not_authored", &"readable", session.snapshot()).ok, "R04 unknown readable is rejected")
	var malformed: Dictionary = session.snapshot()
	malformed.world["cart_coffer"] = {"remaining": 7}
	t.check(not invalid.configure(&"cart_coffer", &"loot", malformed).ok and invalid.model == null, "R04 malformed saved source is rejected before constructing geometry")
	malformed.world["monastery_candle_01"] = {"remaining": 7}
	t.check(not invalid.configure(&"monastery_candle_01", &"loot", malformed).ok, "R04 malformed pickup setup is rejected")
	t.check(invalid.configure(&"toll_notice", &"readable", session.snapshot()).ok and invalid.collision_layer == MireTypes.WORLD, "R04 valid setup after a refused pickup does not inherit its collision rules")
	var candidate: Dictionary = session.snapshot()
	var record: Dictionary = session.world_state.get_entity_state(&"cart_coffer")
	record.opened = true
	record.remaining.clear()
	candidate.world["cart_coffer"] = record
	var before: Dictionary = session.snapshot()
	var prepared: StaticBody3D = _object("cart_coffer", &"loot", candidate)
	t.check(prepared.model.get_node("Lid").rotation.x > 0 and session.state == before, "R38 prepared art uses detached opened/depleted state without replacing live data")
	var listeners: Array[int] = _listeners()
	bus.inventory_changed.emit()
	bus.currency_changed.emit()
	bus.entity_defeated.emit(&"south_cart_cutpurse_01")
	bus.session_restored.emit()
	t.check(_listeners() == listeners and prepared.model.get_node("Lid").rotation.x > 0 and not prepared.interaction.enabled and session.state == before, "R40 staged objects ignore every live refresh event")
	t.check(prepared.activate().ok and is_zero_approx(prepared.model.get_node("Lid").rotation.x), "R38 activation switches presentation to current committed state")
	var children: int = prepared.get_child_count()
	t.check(not prepared.configure(&"cart_coffer", &"loot", candidate).ok and prepared.get_child_count() == children, "R04 repeated configuration cannot duplicate colliders or change identity")
	t.check(not prepared.apply_persistent_state({"opened": "yes"}).ok and is_zero_approx(prepared.model.get_node("Lid").rotation.x), "R38 malformed presentation update leaves the last valid art intact")

func _open_and_loot() -> void:
	_reset()
	var before: Dictionary = session.snapshot()
	var object: StaticBody3D = _object("cart_coffer")
	t.check(not object.interaction.enabled and session.state == before, "R04 prepared loot has no active interaction or domain mutation")
	t.check(object.activate().ok, "R09 loot activates explicitly")
	var opened: MireTypes.ActionResult = object.interaction.interact(&"player", &"open")
	t.check(opened.ok and opened.payload.ui_action == "loot" and opened.payload.entity_id == "cart_coffer", "R25 physical coffer opens the actual loot UI source")
	t.check(session.world_state.get_entity_state(&"cart_coffer").opened and not session.state.key_items.has("cart_medicine"), "R25 opening marks the source without granting contents")
	t.check(object.label == "Cart medicine coffer" and object.interaction.get_offer(&"player").allowed, "R33 opening medicine is available before its quest")
	before = session.snapshot()
	t.check(object.interaction.interact(&"player", &"open").ok and session.state == before, "R34 repeated opening creates no extra receipt or grant")
	t.check(not object.interaction.interact(&"player", &"read").ok and not object.interaction.interact(&"enemy", &"open").ok and session.state == before, "R09 wrong actor and stale action cannot open the source")
	object.entity_id = &"raider_medicine_cache"
	t.check(not object.interaction.interact(&"player", &"open").ok and session.state == before, "R04 identity drift cannot redirect a source")
	object.entity_id = &"cart_coffer"
	t.check(session.world_state.take_loot(&"cart_coffer", &"cart_medicine", 1, &"object/cart").ok, "R25 UI pickup uses the real domain transaction")
	t.check(object.model.visible and object.model.get_node("Lid").rotation.x > 0, "R25 depleted permanent chest remains visibly open")
	before = session.snapshot()
	t.check(not session.world_state.take_loot(&"cart_coffer", &"cart_medicine", 1, &"object/cart_again").ok and session.state == before, "R25 already collected medicine cannot duplicate")
	var reconstructed: StaticBody3D = _object("cart_coffer", &"loot", before)
	t.check(reconstructed.model.visible and reconstructed.model.get_node("Lid").rotation.x > 0 and reconstructed.activate().ok, "R25 empty source reconstruction retains its open appearance")
	var empty: MireTypes.ActionResult = reconstructed.interaction.interact(&"player", &"open")
	t.check(empty.ok and session.world_state.read_loot(&"cart_coffer").payload.empty and session.state == before, "R25 empty permanent containers show honest empty loot without a new grant")
	for id: String in ["kiln_hammer_crate", "ferry_blanket_barrel", "watchtower_badge_locker"]:
		var container: StaticBody3D = _object(id)
		container.activate()
		t.check(container.interaction.interact(&"player", &"open").ok and container.model.get_node("Lid").rotation.x > 0, "R41 crate, barrel and locker each visibly open: " + id)

func _pickups_and_corpses() -> void:
	_reset()
	for source: String in ["monastery_candle_01", "monastery_candle_02", "monastery_candle_03", "shrine_ring_bowl"]:
		var object: StaticBody3D = _object(source)
		object.activate()
		var item: StringName = &"hobb_ring" if source == "shrine_ring_bowl" else &"votive_candle"
		t.check(object.interaction.interact(&"player", &"open").ok and session.world_state.take_loot(StringName(source), item, 1, StringName("object/" + source)).ok, "R25 physical pickup uses its individual fixed source " + source)
		t.check(not object._pickup.visible and not object.interaction.enabled, "R41 collected small pickup disappears and cannot be focused again")
		var reconstructed: StaticBody3D = _object(source)
		reconstructed.activate()
		t.check(not reconstructed._pickup.visible and not reconstructed.interaction.enabled, "R25 reconstructed empty small pickup stays absent")
	t.check(session.state.key_items.votive_candle == 3, "R30 only the three distinct candle sources supply three candles")
	var corpse: StaticBody3D = _object("south_cart_cutpurse_01")
	corpse.activate()
	var before: Dictionary = session.snapshot()
	t.check(corpse.collision_layer == 0 and not corpse.model.visible and not corpse.interaction.interact(&"player", &"open").ok and session.state == before, "R25 a living enemy has no visible or lootable blocking purse")
	t.check(session.world_state.mark_defeated(&"south_cart_cutpurse_01").ok and corpse.model.visible and corpse.interaction.enabled, "R25 committed defeat makes its canonical purse available")
	t.check(corpse.interaction.interact(&"player", &"open").ok and session.state.player.crowns == before.player.crowns, "R25 opening corpse purse does not separately pay currency")
	t.check(session.world_state.take_crowns(&"south_cart_cutpurse_01", &"object/corpse").ok and session.state.player.crowns == before.player.crowns + 4, "R25 corpse UI takes its exact four crowns once")
	t.check(not corpse.model.visible and not corpse.interaction.enabled and corpse.collision_layer == 0, "R25 empty corpse purse disappears without movement collision")
	before = session.snapshot()
	t.check(not session.world_state.take_crowns(&"south_cart_cutpurse_01", &"object/corpse_again").ok and session.state == before, "R25 corpse loot cannot pay twice")
	var saved: StaticBody3D = _object("south_cart_cutpurse_01")
	saved.activate()
	t.check(not saved.model.visible and not saved.interaction.enabled, "R25 corpse reconstruction retains defeat and remaining-loot state")

func _gates_and_readables() -> void:
	_reset()
	var charter: StaticBody3D = _object("charter_vault_coffer")
	var seal: StaticBody3D = _object("captain_seal_chest")
	charter.activate()
	seal.activate()
	var before: Dictionary = session.snapshot()
	t.check(not charter.interaction.get_offer(&"player").allowed and not charter.interaction.interact(&"player", &"open").ok and session.state == before, "R31 charter source refuses access before the vault puzzle")
	t.check(not seal.interaction.get_offer(&"player").allowed and not seal.interaction.interact(&"player", &"open").ok and session.state == before, "R21 seal source refuses access before captain defeat")
	for symbol: StringName in [&"reed", &"stone", &"flame"]: session.quests.ring_chime(symbol)
	t.check(charter.interaction.get_offer(&"player").allowed, "R33 early solved puzzle makes the physical charter accessible")
	session.new_game()
	before = session.snapshot()
	t.check(not charter.interaction.interact(&"player", &"open").ok and session.state == before, "R09 opening rechecks a formerly allowed gate at commit")
	for symbol: StringName in [&"reed", &"stone", &"flame"]: session.quests.ring_chime(symbol)
	t.check(charter.interaction.interact(&"player", &"open").ok and session.world_state.take_loot(&"charter_vault_coffer", &"orra_charter", 1, &"object/charter").ok, "R33 solved-early charter is collectible without accepting MQ03")
	# A genuine completed main-chain fixture supplies defeated Rusk and his opened chest.
	t.check(QuestFixture.ending_checkpoint(session, &"none").ok, "R21 canonical captain-defeated fixture for seal access")
	t.check(seal.interaction.get_offer(&"player").allowed and seal.interaction.interact(&"player", &"open").ok, "R21 actual defeated captain state enables seal chest access")
	_reset()
	for document: String in QuestService.DOCUMENTS:
		var readable: StaticBody3D = _object(document, &"readable")
		readable.activate()
		before = session.snapshot()
		var result: MireTypes.ActionResult = readable.interaction.interact(&"player", &"read")
		if document == "village_writ_table":
			t.check(not result.ok and session.state == before and session.state.quests[QuestPredicates.MQ06].state == "LOCKED", "R29 early writ cannot activate MQ06 or record its review")
			continue
		t.check(result.ok and result.payload.ui_action == "readable" and result.payload.document_id == document and session.state.evidence["read/" + document], "R33 canonical readable returns actual permanent evidence " + document)
		before = session.snapshot()
		result = readable.interaction.interact(&"player", &"read")
		t.check(result.ok and result.payload.replayed and session.state == before, "R34 rereading returns the real receipt without repeating effects")
	var before_review: Array[Dictionary] = []
	var capture := func(evidence_id: StringName) -> void:
		if evidence_id == StringName("conversation/" + QuestPredicates.MQ06 + "/discuss_resolution"):
			before_review.append(session.snapshot())
	bus.evidence_acquired.connect(capture)
	t.check(QuestFixture.ending_checkpoint(session, &"none").ok, "R29 canonical writ-ready fixture")
	bus.evidence_acquired.disconnect(capture)
	t.check(before_review.size() == 1 and session.restore(before_review[0]).ok and not session.state.evidence.get("read/village_writ_table", false), "R29 restore the genuine post-Mara snapshot captured before any writ review")
	var writ: StaticBody3D = _object("village_writ_table", &"readable")
	writ.activate()
	var reviewed: MireTypes.ActionResult = writ.interaction.interact(&"player", &"read")
	t.check(reviewed.ok and reviewed.payload.ui_action == "writ" and session.state.choices.ending == "none" and session.state.evidence["read/village_writ_table"], "R35 physical writ records its first review without choosing an ending")
	before = session.snapshot()
	t.check(writ.interaction.interact(&"player", &"read").payload.replayed and session.state == before, "R35 repeated physical writ review preserves its single receipt and unconfirmed ending")

func _ray_and_lifecycle() -> void:
	_reset()
	var baseline: Array[int] = _listeners()
	var object: StaticBody3D = _object("cart_coffer")
	object.position = Vector3(0, 0, -1.7)
	t.check(object.activate().ok and object.activate().ok and _listeners() == _incremented(baseline), "R40 repeated activation adds exactly one set of object listeners")
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	arena.add_child(player)
	player.set_physics_process(false)
	(player.combat as CombatComponent).input_driven = false
	var host := ModalHost.new()
	arena.add_child(host)
	var modes := GameModeController.new()
	arena.add_child(modes)
	modes.configure(player, host)
	var ray := InteractionRay.new()
	player.add_child(ray)
	ray.configure(player, modes)
	ray.set_physics_process(false)
	# The persistent player also owns subscriptions, separate from the source.
	baseline = _listeners()
	for index: int in baseline.size(): baseline[index] -= 1
	player.camera.look_at(object.interaction.focus_position(), Vector3.UP)
	await _frames()
	ray.refresh_focus()
	t.check(ray.focused == object.interaction, "R09 real eye ray focuses visible coffer through its own physical collider")
	var used: MireTypes.ActionResult = ray.interact_focused()
	t.check(used.ok and used.payload.ui_action == "loot", "R09 real focus commits exactly the physical loot action")
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 0.9, -0.75)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 0.2)
	collider.shape = box
	wall.add_child(collider)
	arena.add_child(wall)
	await _frames()
	ray.refresh_focus()
	t.check(ray.focused == null and not ray.interact_focused().ok, "R09 a real wall blocks the container's interaction area")
	wall.free()
	object.position.z = -4
	player.camera.look_at(object.interaction.focus_position(), Vector3.UP)
	await _frames()
	ray.refresh_focus()
	t.check(ray.focused == null, "R09 physical source obeys the 2.5-meter reach limit")
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(12, 0.2, 12)
	floor_shape.shape = floor_box
	floor_body.position.y = -0.1
	floor_body.add_child(floor_shape)
	arena.add_child(floor_body)
	object.position.z = -1.7
	player.spawn_at(Vector3(0, 0.06, 0), 0)
	await _walk_forward(player)
	t.check(player.global_position.z < -0.5 and player.global_position.z > -1.12, "R41 real player movement collides with the coffer body")
	var bag: StaticBody3D = _object("south_cart_cutpurse_01")
	bag.position = Vector3(2, 0, -0.8)
	bag.activate()
	session.world_state.mark_defeated(&"south_cart_cutpurse_01")
	player.spawn_at(Vector3(2, 0.06, 0), 0)
	await _walk_forward(player)
	t.check(bag.model.visible and player.global_position.z < -1.2, "R25 real player movement passes through a visible corpse purse")
	bag.free()
	object.deactivate()
	object.deactivate()
	t.check(_listeners() == baseline and not object.interaction.enabled, "R40 repeated deactivation removes all listeners and interaction")
	var candidate: Dictionary = session.world_state.get_entity_state(&"cart_coffer")
	candidate.opened = false
	t.check(object.apply_persistent_state(candidate).ok, "R38 detached visual state can be reapplied after deactivation")
	bus.inventory_changed.emit()
	bus.currency_changed.emit()
	bus.session_restored.emit()
	t.check(is_zero_approx(object.model.get_node("Lid").rotation.x), "R40 deactivated object ignores live refresh events")
	t.check(object.activate().ok and object.model.get_node("Lid").rotation.x > 0, "R40 reactivation refreshes the actual opened source")
	var children: int = object.get_child_count()
	arena.remove_child(object)
	t.check(_listeners() == baseline and not object.activate().ok, "R40 tree exit disconnects object listeners")
	arena.add_child(object)
	t.check(object.get_child_count() == children and _listeners() == baseline and not object.interaction.enabled, "R40 tree re-entry preserves art and requires explicit activation")
	t.check(object.activate().ok and _listeners() == _incremented(baseline), "R40 re-entered object binds exactly once")

func _frames() -> void:
	await t.physics_frame
	await t.physics_frame
	await t.process_frame

func _walk_forward(player: MirePlayer) -> void:
	player.set_physics_process(true)
	Input.action_press(&"move_forward")
	for frame: int in 30: await t.physics_frame
	Input.action_release(&"move_forward")
	player.set_physics_process(false)

func _reset() -> void:
	for child: Node in arena.get_children(): child.free()
	session.new_game()

func _listeners() -> Array[int]:
	return [bus.get_signal_connection_list("inventory_changed").size(), bus.get_signal_connection_list("currency_changed").size(), bus.get_signal_connection_list("entity_defeated").size(), bus.get_signal_connection_list("session_restored").size()]

func _incremented(counts: Array[int]) -> Array[int]:
	return [counts[0] + 1, counts[1] + 1, counts[2] + 1, counts[3] + 1]

func _object(id: String, kind: StringName = &"loot", candidate: Dictionary = {}) -> StaticBody3D:
	var object: StaticBody3D = ObjectScript.new()
	object.position.x = 20 + arena.get_child_count() * 3
	arena.add_child(object)
	var result: MireTypes.ActionResult = object.configure(StringName(id), kind, session.snapshot() if candidate.is_empty() else candidate)
	t.check(result.ok, "R04 configure canonical world object " + id + ": " + String(result.message_key))
	return object
