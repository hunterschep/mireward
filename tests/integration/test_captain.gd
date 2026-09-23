extends RefCounted
## Positioned boss fixtures use real combat ticks, parries, UI and durable saves.

const ID: StringName = &"captain_hall_captain_rusk_01"
var t: SceneTree
var game: MireGameRoot
var session: Node
var saves: Node
var boss: CaptainRusk
var patterns: Array[StringName] = []
var parries: Array[StringName] = []
var _last_parry: int = 0
var _held_guard: bool = false
var _attack_release: int = -1

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	saves = t.root.get_node("SaveService")
	var size: Vector2i = t.root.size
	t.root.size = Vector2i(1280,720)
	game = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(game)
	game.router.fade_seconds = 0
	var started: MireTypes.ActionResult = await game.start_new_game(true)
	t.check(started.ok, "T20 begins a real production runtime")
	_pre_mq05()
	await _ada_handoff()
	await _travel(&"interior_undercroft", &"entry")
	boss = _boss()
	await _before_challenge()
	await _pursuer_refusal()
	_clear_retainers()
	game.player.spawn_at(Vector3(0,0,3))
	await _frames(3)
	t.check(saves.save_slot(&"manual_1").ok, "R37 genuine pre-duel checkpoint saves with a living neutral Rusk")
	await _start_duel()
	await _patterns_and_phase()
	await _live_reload()
	await _death_recovery()
	await _start_duel()
	await _fight()
	await _victory_and_reward()
	_release_inputs()
	game.free()
	await t.process_frame
	t.root.size = size
	t.check(not t.paused and session.recovery.player == null, "T20 encounter teardown removes live player/recovery references")

func _pre_mq05() -> void:
	var q: QuestService = session.quests
	var world: WorldStateService = session.world_state
	var main: Array = ContentValidation.REQUIRED_IDS.quest.slice(0, 5)
	var actions: Array[Callable] = [
		func() -> MireTypes.ActionResult: return q.activate(main[0]),
		func() -> MireTypes.ActionResult: return world.take_loot(&"cart_coffer", &"cart_medicine", 1, &"captain/cart"),
		func() -> MireTypes.ActionResult: return q.complete(main[0], &"captain/mq01"),
		func() -> MireTypes.ActionResult: return q.activate(main[1]),
		func() -> MireTypes.ActionResult: return q.read_document(&"toll_notice"),
		func() -> MireTypes.ActionResult: return world.take_loot(&"checkpoint_receipt_box", &"toll_receipt", 1, &"captain/receipt"),
		func() -> MireTypes.ActionResult: return q.complete(main[1], &"captain/mq02"),
		func() -> MireTypes.ActionResult: return q.activate(main[2]),
		func() -> MireTypes.ActionResult: return q.record_conversation(&"sister_elian", StringName(String(main[2]) + "/request_charter")),
		func() -> MireTypes.ActionResult: return q.ring_chime(&"reed"),
		func() -> MireTypes.ActionResult: return q.ring_chime(&"stone"),
		func() -> MireTypes.ActionResult: return q.ring_chime(&"flame"),
		func() -> MireTypes.ActionResult: return world.take_loot(&"charter_vault_coffer", &"orra_charter", 1, &"captain/charter"),
		func() -> MireTypes.ActionResult: return q.complete(main[2], &"captain/mq03"),
		func() -> MireTypes.ActionResult: return q.activate(main[3]),
		func() -> MireTypes.ActionResult: return q.record_conversation(&"wren_kest", StringName(String(main[3]) + "/meet_wren")),
		func() -> MireTypes.ActionResult: return world.take_loot(&"watchtower_ledger_chest", &"grain_ledger", 1, &"captain/ledger"),
		func() -> MireTypes.ActionResult: return q.choose(&"wren_terms", &"amnesty", &"captain/terms"),
		func() -> MireTypes.ActionResult: return q.complete(main[3], &"captain/mq04"),
	]
	for action: Callable in actions:
		var result: MireTypes.ActionResult = action.call()
		t.check(result.ok, "T20 pre-MQ05 fixture advances through genuine domain receipts")
	t.check(session.state.quests[QuestPredicates.MQ05].state == "AVAILABLE" and SaveCodec.validate_snapshot(session.snapshot(), t.root.get_node("ContentDB")).ok, "R29 pre-MQ05 snapshot is legitimate and semantically valid")

func _ada_handoff() -> void:
	await _interact(&"ada_vey")
	await _click("dialogue/accept_mq05")
	await _click("dialogue/@leave")
	await _interact(&"ada_vey")
	await _click("dialogue/record_present_evidence")
	t.check(session.state.flags.undercroft_open and session.state.key_items.orra_charter == 1 and session.state.key_items.grain_ledger == 1, "R29 real Ada handoff opens storehouse and keeps charter/ledger")
	await _click("dialogue/@leave")

func _before_challenge() -> void:
	var world: Node3D = game.router.current_world
	var population: CampaignWorld.Population = world.get_node("CampaignPopulation")
	t.check(population.enemies.size() == 4 and population.coordinator.actors().size() == 4, "R21 undercroft shares one coordinator for three retainers and canonical boss")
	t.check(boss.combat.max_health == 220 and is_equal_approx(boss.combat.armor, 0.2) and boss.combat.faction == &"neutral" and not boss.is_duel_active(), "R21 Rusk begins with220 HP and20%armor, neutral before explicit challenge")
	var ignored := boss.combat.receive_hit(MireTypes.DamageRequest.new(&"player",1000,ID,500,&"heavy",game.player.global_position,&"player"))
	t.check(ignored.outcome == &"ignored" and boss.combat.health == 220 and boss.hurtbox.collision_layer == 0, "R21 unchallenged captain is genuinely invulnerable and has no hostile hurtbox")
	t.check(not boss.challenge().ok and _gate().collision_layer == 0, "R21 arena cannot start without explicit challenge conversation")
	var seal: WorldObject = world.entities[&"captain_seal_chest"]
	t.check(not seal.interaction.get_offer(&"player").allowed, "R33 captain's fixed seal chest requires genuine victory")
	await _interact(ID)
	await _click("dialogue/@leave")
	t.check(not boss.is_duel_active() and _gate().collision_layer == 0 and not session.state.evidence.get("conversation/" + QuestPredicates.MQ05 + "/challenge_rusk",false), "R21 Leave before challenge changes no gate or story step")

func _pursuer_refusal() -> void:
	var raider: EnemyActor = game.router.current_world.entities[&"undercroft_deserter_raider_03"]
	game.player.spawn_at(Vector3(-2,0,-30),0)
	Input.action_press(&"move_forward")
	for frame: int in 300:
		await t.physics_frame
		if game.player.global_position.z < -45.6: break
	Input.action_release(&"move_forward")
	await _frames(12)
	t.check(raider.global_position.z < UndercroftContent.GATE_Z + 0.85 and not raider.combat.dead, "R21 real ordinary AI pursues through the open hall gate")
	await _interact(ID)
	var before: Vector3 = raider.global_position
	await _click("dialogue/challenge_rusk")
	t.check(not boss.is_duel_active() and _gate().collision_layer == 0 and raider.global_position.distance_to(before) < 0.5 and not raider.combat.dead, "R21 pursuing retainer blocks duel safely without teleport, disable or free kill")
	t.check(game.ui.feedback.text.contains("retainers"), "R21 rejected challenge explains the live pursuing retainer")

func _clear_retainers() -> void:
	for actor: EnemyActor in game.router.current_world.get_node("CampaignPopulation").enemies:
		if actor != boss and not actor.combat.dead:
			var result := actor.combat.receive_hit(MireTypes.DamageRequest.new(&"captain_setup",1,actor.entity_id,500,&"heavy",game.player.global_position,&"player"))
			t.check(result.outcome == &"killed", "T20 injected ordinary defeats isolate boss tests through the actual resolver")

func _start_duel() -> void:
	boss = _boss()
	patterns.clear()
	parries.clear()
	_last_parry = 0
	if not boss.combat.phase_changed.is_connected(_phase_changed): boss.combat.phase_changed.connect(_phase_changed)
	if not game.player.combat.hit_received.is_connected(_player_hit): game.player.combat.hit_received.connect(_player_hit)
	await _interact(ID)
	await _click("dialogue/challenge_rusk")
	t.check(boss.is_duel_active() and _gate().collision_layer == MireTypes.WORLD and game.router.is_dangerous(), "R21 actual Challenge starts hostile duel, closes gate and participates in fresh danger")
	t.check(not boss.interaction.enabled and boss.hurtbox.collision_layer == MireTypes.HURTBOX, "R21 duel disables conversation and enables only the real combat hurtbox")

func _patterns_and_phase() -> void:
	for frame: int in 600:
		_parry_inputs(false)
		await t.physics_frame
		if parries.size() >= 2 and boss.breaths_started >= 1: break
	_release_inputs()
	t.check(patterns.size() >= 2 and patterns[0] == &"thrust" and patterns[1] == &"sweep", "R21 actual normal-physics patterns alternate thrust then sweep")
	t.check(parries.size() >= 2 and parries[0] == &"thrust" and parries[1] == &"sweep", "R21 both real active-phase attacks can be parried")
	t.check(boss.breaths_started == 1 and boss.breath_remaining > 0 and boss.breath_remaining <= 0.85, "R21 two attacks create the additional breath opening")
	for frame: int in 300:
		await t.physics_frame
		if boss.combat.phase == &"WINDUP" and boss.combat.phase_elapsed >= 0.15: break
	var profile: Dictionary = boss.combat.attack_profile.duplicate(true)
	var phase: StringName = boss.combat.phase
	var elapsed: float = boss.combat.phase_elapsed
	var spoken: Array[String] = []
	var line: String = t.root.get_node("ContentDB").dialogues[&"captain_rusk"].data.combat_lines.half_health
	var heard := func(message: String) -> void:
		if message == line: spoken.append(message)
	t.root.get_node("EventBus").feedback.connect(heard)
	boss.combat.receive_hit(MireTypes.DamageRequest.new(&"phase_fixture",1,ID,150,&"light",game.player.global_position,&"player"))
	t.check(boss.phase_two and boss.combat.health == 100 and boss.combat.phase == phase and boss.combat.phase_elapsed == elapsed and boss.combat.attack_profile == profile, "R21 threshold during committed attack preserves its full current timings and damage window")
	boss.combat.receive_hit(MireTypes.DamageRequest.new(&"phase_fixture",2,ID,1,&"light",game.player.global_position,&"player"))
	t.check(spoken.size() == 1, "R21 canonical half-health line fires once per encounter")
	var next_sequence: int = boss.combat.attack_sequence
	for frame: int in 500:
		_parry_inputs(false)
		await t.physics_frame
		if boss.combat.phase == &"WINDUP" and boss.combat.attack_sequence != next_sequence: break
	_release_inputs()
	var current: Dictionary = boss.combat.attack_profile
	var authored: Dictionary = CaptainRusk.PROFILES[boss.combat.attack_kind]
	t.check(is_equal_approx(current.recovery, float(authored.recovery)*0.85) and current.windup == authored.windup and current.active == authored.active and current.damage == authored.damage, "R21 phase two shortens only future recovery by exactly15%")
	t.root.get_node("EventBus").feedback.disconnect(heard)

func _live_reload() -> void:
	_release_inputs()
	await _frames(2)
	t.check(not saves.save_slot(&"manual_2").ok and boss.is_duel_active(), "R39 saving remains forbidden during the actual active duel")
	game.modes.push_mode(&"pause")
	var restored: MireTypes.ActionResult = await game.load_slot(&"manual_1")
	t.check(restored.ok, "R21 paused explicit Load restores a live encounter at an idle player boundary")
	boss = _boss()
	t.check(boss.combat.health == 220 and not boss.phase_two and not boss.is_duel_active() and _gate().collision_layer == 0 and not session.state.world.get(String(ID),{}).get("defeated",false), "R21 real load resets living Rusk completely and grants no victory")

func _death_recovery() -> void:
	await _start_duel()
	var crowns: int = session.state.player.crowns
	game.player.combat.receive_hit(MireTypes.DamageRequest.new(ID,999999,&"player",500,&"heavy",boss.global_position,&"hostile"))
	await _frames(2)
	t.check(game.modes.mode == &"death" and _gate().collision_layer == 0 and not boss.is_duel_active(), "R21 actual player death opens the arena immediately")
	await _click("death/recover")
	await _wait_scene(&"exterior")
	t.check(session.state.player.health == 100 and session.state.player.crowns == crowns - mini(12,floori(crowns*0.1)) and not session.state.key_items.has("rookwatch_seal"), "R22 real death recovery charges once and never grants the seal")
	await _travel(&"interior_undercroft",&"entry")
	boss = _boss()
	t.check(boss.combat.health == 220 and not boss.is_duel_active() and _gate().collision_layer == 0, "R21 returning after recovery leaves living Rusk full-health and unchallenged")

func _fight() -> void:
	var health: float = session.state.player.health
	var started: int = Time.get_ticks_msec()
	for frame: int in 3000:
		_parry_inputs(true)
		await t.physics_frame
		if boss.combat.dead or float(session.state.player.health) <= 0: break
	_release_inputs()
	await _frames(3)
	t.check(boss.combat.dead and float(session.state.player.health) > 0, "R21 normal-physics parry/counter strategy defeats full-health220 Rusk with borrowed gear")
	t.check(parries.size() >= 10 and boss.phase_two and boss.attacks_started >= 10, "R21 credible fight executes repeated live patterns, parries and both phases")
	t.check(_gate().collision_layer == 0 and session.state.world.get(String(ID),{}).get("defeated",false) and not session.state.key_items.has("rookwatch_seal"), "R21 real victory persists once and opens gate without auto-granting seal")
	print("CAPTAIN_FIGHT " + JSON.stringify({"seconds":(Time.get_ticks_msec()-started)/1000.0,"parries":parries.size(),"attacks":boss.attacks_started,"breaths":boss.breaths_started,"player_health_before":health,"player_health_after":session.state.player.health,"boss_dead":boss.combat.dead}))

func _victory_and_reward() -> void:
	if not boss.combat.dead: return
	await _travel(&"exterior",&"from_undercroft")
	game.player.spawn_at(Vector3(32,0,252))
	await _frames(20)
	t.check(saves.save_slot(&"manual_2").ok, "S11 victory before seal pickup writes a real save")
	var restored: MireTypes.ActionResult = await game.load_slot(&"manual_2")
	t.check(restored.ok, "S11 victory-before-loot save reloads without granting loot")
	await _travel(&"interior_undercroft",&"entry")
	boss = _boss()
	t.check(boss.combat.dead and not boss.interaction.enabled and _gate().collision_layer == 0, "S11 reloaded defeated Rusk remains dead and cannot be challenged")
	t.check(game.router.current_world.entities[&"captain_seal_chest"].interaction.get_offer(&"player").allowed, "S11 fixed seal remains accessible independently of corpse physics")
	var purse: MireTypes.ActionResult = session.world_state.read_loot(ID)
	t.check(purse.ok and purse.payload.crowns == 18, "R25 boss corpse retains its separate18 unclaimed crowns without auto-award")
	session.inventory.try_add(&"arming_sword",16-session.state.inventory.size(),&"captain/full_pack")
	await _interact(&"captain_seal_chest")
	await _click("take/rookwatch_seal")
	game.modes.push_mode(&"gameplay")
	t.check(session.state.quests[QuestPredicates.MQ05].state == "READY", "R29 actual fixed seal pickup makes Ada report ready")
	await _travel(&"exterior",&"from_undercroft")
	await _interact(&"ada_vey")
	var crowns: int = session.state.player.crowns
	await _click("dialogue/complete_mq05")
	t.check(session.state.player.crowns == crowns+40 and session.state.pending_delivery.has(QuestPredicates.MQ05+"/watchblade") and session.state.quests[QuestPredicates.MQ06].state == "AVAILABLE", "R29 real Ada report pays40 and queues Watchblade at capacity while unlocking MQ06")
	var replay: MireTypes.ActionResult = session.quests.complete(StringName(QuestPredicates.MQ05),&"captain/repeat_report")
	t.check(replay.ok and replay.payload.replayed and session.state.player.crowns == crowns+40, "R34 repeated completed captain report cannot pay twice")
	await _click("dialogue/@leave")
	game.player.spawn_at(Vector3(32,0,252))
	await _frames(20)
	t.check(saves.save_slot(&"manual_3").ok, "R37 complete MQ05 produces a legitimate pre-ending checkpoint")

func _parry_inputs(counterattack: bool) -> void:
	if boss.combat.phase == &"WINDUP" and boss.combat.phase_elapsed >= float(boss.combat.attack_profile.windup)-0.11 and not _held_guard and not game.player.combat.is_committed():
		Input.action_press(&"block")
		_held_guard = true
	if parries.size() > _last_parry:
		_last_parry = parries.size()
		Input.action_release(&"block")
		_held_guard = false
		if counterattack:
			Input.action_press(&"attack_light")
			_attack_release = Engine.get_physics_frames()+2
	if _attack_release >= 0 and Engine.get_physics_frames() >= _attack_release:
		Input.action_release(&"attack_light")
		_attack_release = -1

func _phase_changed(phase: StringName) -> void:
	if phase == &"WINDUP": patterns.append(boss.combat.attack_kind)

func _player_hit(request: MireTypes.DamageRequest, result: MireTypes.DamageResult) -> void:
	if request.attacker_id == ID and result.outcome == &"parried": parries.append(request.attack_kind)

func _release_inputs() -> void:
	for action: StringName in [&"block",&"attack_light",&"move_forward"]: Input.action_release(action)
	_held_guard = false
	_attack_release = -1

func _boss() -> CaptainRusk:
	return game.router.current_world.entities[ID]

func _gate() -> StaticBody3D:
	return game.router.current_world.entities[UndercroftContent.GATE_ID]

func _interact(id: StringName) -> void:
	game.modes.push_mode(&"gameplay")
	await _frames(2)
	var target: Node3D = game.router.current_world.entities[id]
	var component: InteractionComponent = target if target is InteractionComponent else target.interaction
	var base: Vector3 = target.global_position
	base.y = 0
	var reached: bool = false
	for direction: Vector3 in [-target.global_basis.z,Vector3.BACK,Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD]:
		var at: Vector3 = base+direction*1.7
		if not game.router.validate_anchor(game.router.current_world,Transform3D(Basis.IDENTITY,at)).ok: continue
		var toward: Vector3 = component.focus_position() - at
		game.player.spawn_at(at, atan2(-toward.x, -toward.z))
		var sight: Vector3 = component.focus_position() - game.player.camera.global_position
		var pitch: float = atan2(sight.y, Vector2(sight.x, sight.z).length())
		game.player.apply_look(Vector2(0, -pitch / float(saves.settings.mouse_sensitivity)))
		await _frames(2)
		game.interaction.refresh_focus()
		if game.interaction.focused == component:
			reached = true
			break
	t.check(reached,"R09 actual spatial focus reaches "+String(id))
	if reached:
		var result := game.interaction.interact_focused()
		t.check(result.ok,"R09 actual physical adapter succeeds: "+String(id))
	await _frames(2)

func _click(id: String) -> void:
	var button: Button
	for node: Node in game.modal_host.find_children("*","Button",true,false):
		if node.get_meta("ui_id","")==id and node.is_visible_in_tree():
			button=node
			break
	t.check(button!=null and not button.disabled,"T20 actual UI control available: "+id)
	if button!=null and not button.disabled: button.pressed.emit()
	await _frames(3)

func _travel(scene: StringName, entry: StringName) -> void:
	for frame: int in 90:
		if not game.player.combat.is_committed() and not session.action_locked:
			break
		await t.physics_frame
	var requested := game.router.travel(scene,entry)
	t.check(requested.ok,"T20 fixture requests actual scene travel: "+String(scene))
	await _wait_scene(scene)

func _wait_scene(scene: StringName) -> void:
	for frame: int in 240:
		if not session.travelling and game.router.loaded_scene_id==scene: break
		await t.physics_frame
	t.check(not session.travelling and game.router.loaded_scene_id==scene,"R06 actual world arrival completes: "+String(scene))
	await _frames(3)

func _frames(count: int) -> void:
	for frame: int in count: await t.physics_frame
	await t.process_frame
