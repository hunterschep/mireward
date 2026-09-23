extends RefCounted
## Positioned integration fixtures; actual production E/Enter controls commit MQ04.

const MQ04 := "mq_04_names_in_the_ledger"
const MQ05 := "mq_05_a_debt_in_stone"
const SQ05 := "sq_05_the_broken_badge"
const SQ06 := "sq_06_no_clean_hands"
const WATCHTOWER: Array[StringName] = [&"watchtower_deserter_raider_01", &"watchtower_deserter_raider_02", &"watchtower_cutpurse_03"]
var t: SceneTree
var session: Node
var saves: Node
var game: MireGameRoot
var old_loot: Dictionary = {}
var outcomes: Dictionary = {}
var walked: Array[Dictionary] = []

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	saves = t.root.get_node("SaveService")
	var original_size: Vector2i = t.root.size
	t.root.size = Vector2i(1280, 720)
	game = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(game)
	game.router.fade_seconds = 0
	var started: MireTypes.ActionResult = await game.start_new_game(true)
	t.check(started.ok, "T19 begins a real production campaign")
	if started.ok:
		await _pre_mq04()
		if session.state.quests[MQ04].state == "AVAILABLE":
			await _branch(&"amnesty", false, &"manual_1")
			await _branch(&"restitution", true, &"manual_2")
			if outcomes.size() == 2:
				t.check(outcomes.amnesty == outcomes.restitution, "R34 both terms preserve identical report reward, MQ05 access, inventory and old loot")
	await _frames(2)
	game.free()
	await t.process_frame
	t.root.size = original_size
	t.check(not t.paused and session.recovery.player == null, "T19 real root teardown releases player, modes and runtime bindings")
	print("LEDGER_ARC_ROUTES " + JSON.stringify(walked))

func _pre_mq04() -> void:
	# Root-approved reuse of the existing T18 production UI fixture, without running
	# its separate malformed/rollback tests or fabricating completed quest records.
	var prelude: RefCounted = load("res://tests/integration/test_monastery_arc.gd").new()
	prelude.set("t", t)
	prelude.set("session", session)
	prelude.set("saves", saves)
	prelude.set("game", game)
	prelude.set("crypt", game.crypt)
	await prelude._complete_first_two()
	await prelude._request_charter()
	await prelude._enter_crypt()
	prelude._clear_keepers()
	for symbol: StringName in [&"reed", &"stone", &"flame"]:
		await prelude._ring(symbol)
	await prelude._take_charter()
	await prelude._exit_crypt()
	await prelude._attest()
	t.check(session.state.quests[MQ04].state == "AVAILABLE" and session.state.player.crowns == 80, "T19 pre-MQ04 checkpoint derives from genuine MQ01-MQ03 UI receipts")
	# A partially looted encounter: one opened purse retains all four crowns,
	# while the other has been claimed. Canonical purses have no fractional API.
	for id: StringName in [&"south_cart_cutpurse_01", &"south_cart_cutpurse_02"]:
		_defeat(id)
		await _interact(id)
		if id == &"south_cart_cutpurse_02": await _ui("take/crowns")
		await _back()
		old_loot[String(id)] = session.world_state.get_entity_state(id)
	t.check(old_loot.south_cart_cutpurse_01.opened and old_loot.south_cart_cutpurse_01.crowns_remaining == 4 and old_loot.south_cart_cutpurse_02.crowns_remaining == 0, "R25 checkpoint retains distinct unclaimed and depleted corpse sources")
	await _safe()
	var saved: MireTypes.ActionResult = saves.save_slot(&"manual_3")
	t.check(saved.ok and saves.inspect_slot(&"manual_3").payload.snapshot.quests[MQ04].state == "AVAILABLE", "R37 actual baseline save is pre-MQ04 and semantically validated")

func _branch(terms: StringName, early: bool, slot: StringName) -> void:
	await _safe()
	var loaded: MireTypes.ActionResult = await game.load_slot(&"manual_3")
	t.check(loaded.ok and session.state.choices.wren_terms == "unset", "R38 branch reload starts from the same legitimate baseline: " + String(terms))
	await _frames(3)
	_neutrals()
	var world: Node3D = game.router.current_world
	for id: StringName in WATCHTOWER:
		var actor: EnemyActor = world.entities[id]
		t.check(actor.entity_id == id and not actor.combat.dead and actor.definition.id == (&"cutpurse" if id == &"watchtower_cutpurse_03" else &"deserter_raider"), "R18 watchtower has the authored live actor: " + String(id))
	if early:
		await _collect_documents()
		t.check(session.state.quests[MQ04].state == "AVAILABLE" and session.state.key_items.grain_ledger == 1, "R33 ledger can be acquired before MQ04 acceptance")
	await _interact(&"wren_kest")
	t.check(_button("dialogue/offer_sq06") != null and _button("dialogue/ask_grain") != null, "R32 main offer does not hide Wren's side quest or grain context")
	await _ui("dialogue/accept_mq04")
	t.check(not session.state.evidence.get("conversation/" + MQ04 + "/meet_wren", false) and session.state.choices.wren_terms == "unset", "R29 acceptance is distinct from meeting and testimony")
	await _ui("dialogue/@leave")
	await _interact(&"wren_kest")
	t.check(_button("dialogue/record_meet_wren") != null, "R29 Wren's account meeting has its own actual control")
	await _ui("dialogue/record_meet_wren")
	t.check(session.state.evidence.get("conversation/" + MQ04 + "/meet_wren", false) and session.state.choices.wren_terms == "unset", "R29 the meeting alone cannot commit testimony terms")
	await _ui("dialogue/@leave")
	if not early: await _collect_documents()
	await _watchtower_walk()
	await _interact(&"wren_kest")
	t.check(_button("dialogue/review_amnesty") != null and _button("dialogue/review_restitution") != null and _button("dialogue/offer_sq06") != null, "R32 both material terms and unrelated side option are accessible")
	var before: Dictionary = session.snapshot()
	await _ui("dialogue/review_" + String(terms))
	t.check(session.dialogue.view().confirmation and _text().contains("permanent") and _text().contains("thirty-crown") and session.snapshot() == before, "R34 reviewing a material choice discloses consequence and reward without mutation")
	var stale: Callable = _callback("dialogue/confirm_" + String(terms))
	await _ui("dialogue/cancel_terms")
	t.check(session.snapshot() == before, "R34 Cancel applies no terms, reward or ledger consumption")
	if stale.is_valid(): stale.call()
	await _frames(2)
	t.check(session.snapshot() == before and session.state.choices.wren_terms == "unset", "R34 old confirmation callback is rejected after cancelling")
	await _ui("dialogue/@leave")
	await _save_reload(slot)
	t.check(session.state.choices.wren_terms == "unset" and session.state.evidence.get("conversation/" + MQ04 + "/meet_wren", false) and session.state.key_items.grain_ledger == 1, "R38 reload before terms preserves meeting and acquired ledger without inventing a promise")
	await _interact(&"wren_kest")
	await _ui("dialogue/review_" + String(terms))
	var repeat: Callable = _callback("dialogue/confirm_" + String(terms))
	var crowns: int = session.state.player.crowns
	await _ui("dialogue/confirm_" + String(terms))
	t.check(session.state.choices.wren_terms == String(terms) and session.state.quests[MQ04].state == "READY" and session.state.player.crowns == crowns and session.state.key_items.grain_ledger == 1, "R34 confirmed testimony stores only the selected terms; Mara owns the reward")
	var committed: Dictionary = session.snapshot()
	if repeat.is_valid():
		repeat.call()
		repeat.call()
	await _frames(2)
	t.check(session.snapshot() == committed, "R34 duplicate stale UI callbacks cannot change terms or pay money")
	t.check(_button("dialogue/offer_sq06") != null and _button("dialogue/ask_grain") != null, "R32 committed terms preserve Wren's unrelated topics")
	await _ui("dialogue/@leave")
	await _save_reload(slot)
	t.check(session.state.choices.wren_terms == String(terms) and session.state.transactions.has("choice/wren_terms") and session.state.player.crowns == crowns, "R38 post-terms file reload retains exactly one testimony receipt")
	_neutrals()
	_old_sources()
	await _interact(&"wren_kest")
	await _ui("dialogue/offer_sq06")
	await _ui("dialogue/accept_sq06")
	t.check(session.state.quests[SQ06].state == "ACTIVE" and session.state.choices.medicine_recipient == "unset", "R32 No Clean Hands remains independently acceptable after either Wren promise")
	await _ui("dialogue/@leave")
	await _interact(&"mara_venn")
	var report: Callable = _callback("dialogue/complete_mq04")
	await _ui("dialogue/complete_mq04")
	t.check(session.state.player.crowns == crowns + 30 and session.state.quests[MQ04].state == "COMPLETED" and session.state.quests[MQ05].state == "AVAILABLE", "R29 actual Mara report pays thirty once and unlocks MQ05")
	committed = session.snapshot()
	if report.is_valid():
		report.call()
		report.call()
	await _frames(2)
	t.check(session.snapshot() == committed, "R34 duplicate Mara callbacks cannot pay the report twice")
	await _ui("dialogue/@leave")
	await _interact(&"oswin_pike")
	await _ui("dialogue/open_shop")
	t.check(game.modes.mode == &"shop" and _button("buy/arming_sword") != null, "R26 genuine Oswin shop access remains after either terms branch")
	await _back()
	await _interact(&"ada_vey")
	t.check(_button("dialogue/accept_mq05") != null and session.state.quests[MQ05].state == "AVAILABLE", "R29 Ada physically offers MQ05 after either promise without changing its access requirements")
	await _ui("dialogue/@leave")
	await _save_reload(slot)
	t.check(session.state.quests[MQ05].state == "AVAILABLE" and session.state.player.crowns == crowns + 30, "R38 final MQ05-unlocked checkpoint reload cannot repeat the report reward")
	_old_sources()
	outcomes[String(terms)] = {"crowns": session.state.player.crowns, "mq05": session.state.quests[MQ05].state, "undercroft_open": session.state.flags.undercroft_open, "inventory": session.state.inventory.duplicate(true), "keys": session.state.key_items.duplicate(true), "old_loot": {"first": session.state.world.south_cart_cutpurse_01.duplicate(true), "second": session.state.world.south_cart_cutpurse_02.duplicate(true)}}

func _collect_documents() -> void:
	await _interact(&"watchtower_ledger_chest")
	await _ui("take/grain_ledger")
	t.check(session.state.key_items.get("grain_ledger", 0) == 1 and session.state.evidence.get("pickup/watchtower_ledger_chest", false), "R33 actual watchtower chest UI collects canonical grain evidence")
	await _back()
	await _interact(&"watchtower_badge_locker")
	await _ui("take/ada_badge")
	t.check(session.state.quests[SQ05].state == "AVAILABLE" and session.state.key_items.get("ada_badge", 0) == 1, "R33 badge locker works physically before SQ05 acceptance")
	await _back()

func _neutrals() -> void:
	var details: ExteriorContent = game.router.current_world.get_node("CampaignPopulation").details
	t.check(details.residents.size() == 4, "R32 camp and courtyard retain all four neutral residents")
	for resident: StaticBody3D in details.residents:
		t.check(resident.collision_layer == MireTypes.NEUTRAL and resident.find_children("*", "CombatComponent", true, false).is_empty() and resident.find_children("*", "CombatHurtbox", true, false).is_empty(), "R32 unnamed camp/courtyard actor cannot become a hostile or damage target")
	for id: StringName in [&"wren_kest", &"ada_vey"]:
		var npc: NpcActor = game.router.current_world.entities[id]
		t.check(npc.collision_layer == MireTypes.NEUTRAL and npc.find_children("*", "CombatHurtbox", true, false).is_empty(), "R32 named noncombat speaker remains invulnerable: " + String(id))

func _old_sources() -> void:
	for id: String in old_loot:
		t.check(session.world_state.get_entity_state(StringName(id)) == old_loot[id] and game.router.current_world.entities[StringName(id)].combat.dead, "R38 old defeat and remaining/depleted purse persist: " + id)
	for id: String in ["crypt_hollow_keeper_01", "crypt_hollow_keeper_02", "crypt_hollow_keeper_03", "crypt_hollow_keeper_04"]:
		t.check(session.state.world.get(id, {}).get("defeated", false), "R38 prior crypt defeat survives the exterior arc: " + id)

func _defeat(id: StringName) -> void:
	var actor: EnemyActor = game.router.current_world.entities[id]
	if actor.combat.dead: return
	var result := actor.combat.receive_hit(MireTypes.DamageRequest.new(&"ledger_fixture", 1, id, 200, &"heavy", game.player.global_position, &"player"))
	t.check(result.outcome == &"killed" and session.state.world[String(id)].defeated, "T19 disclosed damage fixture clears a canonical actor through live defeat hooks")

func _watchtower_walk() -> void:
	# Clear the three real actors to isolate doorway/approach movement, not combat.
	for id: StringName in WATCHTOWER: _defeat(id)
	game.modes.push_mode(&"gameplay")
	game.player.spawn_at(Vector3(182, 0, -218))
	await _frames(3)
	for at: Vector3 in [Vector3(181.2, 0, -219.5), Vector3(176, 0, -220), Vector3(176, 0, -222.8), Vector3(177, 0, -222.8), Vector3(177, 0.168, -226.1)]:
		await _walk_to(at)

func _walk_to(goal: Vector3) -> void:
	var start: Vector3 = game.player.global_position
	var closest: float = Vector2(start.x - goal.x, start.z - goal.z).length()
	var distance: float = 0
	var jumped: bool = false
	var walking: bool = false
	for frame: int in 240:
		var offset: Vector3 = goal - game.player.global_position
		var remaining := Vector2(offset.x, offset.z).length()
		var speed := Vector2(game.player.velocity.x, game.player.velocity.z).length()
		if remaining < 0.15 and speed < 0.3: break
		game.player.rotation.y = atan2(-offset.x, -offset.z)
		var should_walk: bool = remaining > maxf(0.08, speed * speed / (2 * MirePlayer.ACCELERATION) + 0.06)
		if should_walk != walking:
			_set_action(&"move_forward", should_walk)
			walking = should_walk
		var before: Vector3 = game.player.global_position
		await t.physics_frame
		distance += before.distance_to(game.player.global_position)
		closest = minf(closest, Vector2(game.player.global_position.x - goal.x, game.player.global_position.z - goal.z).length())
		if frame == 100 and closest > 0.18 and game.player.is_on_floor():
			_set_action(&"jump", true)
			jumped = true
		elif frame == 102: _set_action(&"jump", false)
	_set_action(&"move_forward", false)
	_set_action(&"jump", false)
	await _frames(3)
	var final_distance := Vector2(game.player.global_position.x - goal.x, game.player.global_position.z - goal.z).length()
	if closest >= 0.18:
		var contacts: Array[Dictionary] = []
		for index: int in game.player.get_slide_collision_count():
			var contact := game.player.get_slide_collision(index)
			var collider: Object = contact.get_collider()
			contacts.append({"collider": String(collider.get_path()) if collider is Node else str(collider), "normal": contact.get_normal(), "position": contact.get_position()})
		print("LEDGER_ROUTE_CONTACTS " + JSON.stringify({"goal": goal, "player": game.player.global_position, "contacts": contacts}))
	t.check(final_distance < 0.2 and game.player.is_on_floor(), "R07 actual normal-speed movement reaches the watchtower source/doorway approach")
	walked.append({"from": [start.x, start.y, start.z], "target": [goal.x, goal.y, goal.z], "walked": distance, "closest": closest, "final_distance": final_distance, "jump_used": jumped})

func _interact(id: StringName) -> bool:
	game.modes.push_mode(&"gameplay")
	await _frames(2)
	var world: Node3D = game.router.current_world
	var target: Node3D = world.entities.get(id)
	if target is EnemyActor: target = world.get_node("CampaignPopulation").purses[id]
	t.check(target != null, "T19 canonical physical target exists: " + String(id))
	if target == null: return false
	var component: InteractionComponent = target.interaction
	var focused: bool = false
	for direction: Vector3 in [-target.global_basis.z, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD]:
		var at: Vector3 = target.global_position + direction * 1.6
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.5, at - Vector3.UP, MireTypes.WORLD)
		var floor_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		if not floor_hit.is_empty(): at.y = floor_hit.position.y
		if not game.router.validate_anchor(world, Transform3D(Basis.IDENTITY, at)).ok: continue
		game.player.spawn_at(at)
		game.player.camera.look_at(component.focus_position(), Vector3.UP)
		await _frames(3)
		game.interaction.refresh_focus()
		if game.interaction.focused == component and game.interaction.offer.allowed:
			focused = true
			break
	t.check(focused, "R09 clear grounded ray approach reaches " + String(id))
	if not focused: return false
	_set_action(&"interact", true)
	await _frames(1)
	_set_action(&"interact", false)
	await _frames(3)
	var expected: StringName = &"dialogue" if target is NpcActor else &"inventory"
	t.check(game.modes.mode == expected, "R09 bound E input opens the actual dialogue or source panel: " + String(id))
	return game.modes.mode == expected

func _ui(id: String) -> bool:
	var button := _button(id)
	t.check(button != null and not button.disabled, "T19 actual UI control is available: " + id)
	if button == null or button.disabled: return false
	button.grab_focus()
	await _frames(2)
	_key(KEY_ENTER, true)
	await _frames(1)
	_key(KEY_ENTER, false)
	await _frames(3)
	return true

func _button(id: String) -> Button:
	for node: Node in game.modal_host.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and node.get_meta("ui_id", "") == id: return node
	return null

func _callback(id: String) -> Callable:
	var button := _button(id)
	t.check(button != null, "R34 capture the existing real UI callback for stale-delivery testing")
	return button.pressed.get_connections()[0].callable if button != null else Callable()

func _save_reload(slot: StringName) -> void:
	await _safe()
	await _back()
	await _ui("pause/save")
	await _ui("save/" + String(slot))
	if game.modes.mode == &"confirmation": await _ui("confirmation/confirm")
	t.check(saves.inspect_slot(slot).ok, "R37 actual save panel writes a validated ledger checkpoint")
	await _back()
	await _ui("pause/load")
	await _ui("load/" + String(slot))
	for frame: int in 240:
		if not saves.is_loading() and not session.travelling and not game.ui._busy: break
		await t.physics_frame
	await _frames(3)
	t.check(game.modes.mode == &"gameplay" and game.router.loaded_scene_id == &"exterior", "R38 actual load control waits for reconstructed exterior arrival")

func _safe() -> void:
	game.modes.push_mode(&"gameplay")
	game.player.spawn_at(Vector3(32, 0, 252))
	await _frames(20)
	t.check(not game.router.is_dangerous(), "T19 positioned save fixture uses a truly safe exterior anchor")

func _back() -> void:
	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(3)

func _set_action(action: StringName, pressed: bool) -> void:
	var event: InputEvent = InputMap.action_get_events(action)[0].duplicate()
	event.set("pressed", pressed)
	if event is InputEventKey: event.keycode = event.physical_keycode
	Input.parse_input_event(event)

func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func _text() -> String:
	var text := ""
	for node: Node in game.ui.panels[&"dialogue"].find_children("*", "Label", true, false): text += node.text + "\n"
	return text

func _frames(count: int) -> void:
	for frame: int in count: await t.physics_frame
	await t.process_frame
