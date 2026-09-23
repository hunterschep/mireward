extends RefCounted

class DangerRouter extends WorldRouter:
	var forced_danger: bool = false
	var danger_reads: int = 0
	func is_dangerous() -> bool:
		danger_reads += 1
		return forced_danger or super.is_dangerous()

class ArrivalBlocker extends StaticBody3D:
	var entries: int = 0
	func _enter_tree() -> void:
		entries += 1
		collision_layer = MireTypes.WORLD if entries > 1 else 0

var t: SceneTree
var session: Node
var saves: Node
var router: DangerRouter
var player: MirePlayer
var modes: GameModeController
var _autosaves: Array[Dictionary] = []

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	saves = t.root.get_node("SaveService")
	session.new_game()
	var container := Node3D.new()
	t.root.add_child(container)
	player = load("res://scenes/player/player.tscn").instantiate()
	t.root.add_child(player)
	player.set_physics_process(false)
	player.combat.input_driven = false
	var host := ModalHost.new()
	t.root.add_child(host)
	modes = GameModeController.new()
	t.root.add_child(modes)
	modes.configure(player, host)
	router = DangerRouter.new()
	t.root.add_child(router)
	router.fade_seconds = 0
	t.check(router.configure(player, container, modes).ok, "R39 bind actual player, modes and world router")
	var accepted := router.travel(&"interior_inn", &"entry")
	t.check(accepted.ok, "R39 prepare a real loaded world")
	var arrived: Array = await router.travel_completed
	t.check(arrived[1].ok, "R39 real inn arrival completes before save binding")
	t.check(session.recovery.bind_runtime(player, router.is_dangerous, router.reset_living_encounters, router.recovery_travel).ok, "R39 bind real healing and recovery")
	t.check(saves.bind_runtime(player, router).ok, "R39 bind persistence to the live world")
	saves.set_physics_process(false)
	saves.autosave_finished.connect(_on_autosave)
	await _safety_and_queue()
	await _load_isolation()
	await _ending_failures()
	await _lifecycle()
	await t.process_frame
	saves.autosave_finished.disconnect(_on_autosave)
	saves.unbind_runtime()
	saves.set_physics_process(true)
	session.recovery.unbind_runtime()
	router.free()
	container.free()
	player.free()
	modes.free()
	host.free()
	t.paused = false
	session.new_game()
	await t.physics_frame

func _safety_and_queue() -> void:
	t.check(saves.save_slot(&"manual_1").ok, "R37 manual save writes a real loaded scene")
	var recorded: MireTypes.ActionResult = saves.inspect_slot(&"manual_1")
	t.check(recorded.ok and recorded.payload.snapshot.player.scene_id == "interior_inn" and recorded.payload.snapshot.player.position == [0.0, 0.0, 3.0], "R37 save records the scene's canonical safe anchor")
	var manual := FileAccess.get_file_as_string(saves.slot_path(&"manual_1"))
	for flag: String in ["travelling", "action_locked"]:
		session.set(flag, true)
		t.check(not saves.save_slot(&"manual_1").ok, "R39 manual save refuses " + flag)
		session.set(flag, false)
	session.transactions.active = true
	t.check(not saves.save_slot(&"manual_1").ok, "R39 manual save refuses transaction in progress")
	session.transactions.active = false
	router.forced_danger = true
	session.danger = false
	var reads := router.danger_reads
	t.check(saves.save_slot(&"manual_1").code == &"danger" and router.danger_reads > reads, "R39 fresh encounter danger overrides stale cached safety")
	modes.push_mode(&"pause")
	modes.push_mode(&"load")
	t.check((await saves.load_slot(&"manual_1")).ok and modes.mode == &"gameplay", "R21 paused load can replace a dangerous encounter at a committed state boundary")
	t.check(router.forced_danger and not saves.save_slot(&"manual_1").ok, "R39 allowing encounter reload does not permit dangerous saves")
	saves.request_autosave(&"quest_completed")
	saves.request_autosave(&"quest_completed")
	saves.request_autosave(&"rest")
	saves._physics_process(0.1)
	t.check(saves.pending_autosave().pending and not FileAccess.file_exists(saves.slot_path(&"autosave")), "R39 unsafe autosaves wait without writing")
	t.check(session.inventory.try_add(&"bread", 1, &"save/queued_bread").ok, "R39 mutate committed inventory while the autosave is queued")
	router.forced_danger = false
	saves._physics_process(0.1)
	var saved: MireTypes.ActionResult = saves.inspect_slot(&"autosave")
	t.check(saved.ok and saved.payload.snapshot.transactions.has("inventory/add/save/queued_bread"), "R39 queued autosave snapshots latest committed state")
	t.check(_autosaves.size() == 1 and not saves.pending_autosave().pending, "R39 repeated requests coalesce into one completed autosave")
	t.check(FileAccess.get_file_as_string(saves.slot_path(&"manual_1")) == manual, "R37 autosave never overwrites a manual slot")
	player.combat.request_attack(&"light")
	t.check(not saves.save_slot(&"manual_1").ok, "R39 committed attack refuses a save")
	player.combat.reset_combat()
	player.combat.set_guard(true)
	t.check(not saves.save_slot(&"manual_1").ok, "R39 guarding refuses a save")
	player.combat.set_guard(false)
	session.state.player.health = 50.0
	t.check(session.recovery.start_consume(&"stack_4").ok, "R39 start genuine timed healing")
	t.check(not saves.save_slot(&"manual_1").ok and not (await saves.load_slot(&"manual_1")).ok, "R39 live healing refuses save and load")
	session.recovery.cancel_consume()

func _load_isolation() -> void:
	var before: Dictionary = session.snapshot()
	var world: Node3D = router.current_world
	var bad_path: String = saves.slot_path(&"manual_2")
	var file := FileAccess.open(bad_path, FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	t.check(not (await saves.load_slot(&"manual_2")).ok and session.snapshot() == before and router.current_world == world, "R39 malformed candidate leaves exact current session and world playable")
	modes.push_mode(&"pause")
	modes.push_mode(&"load")
	modes.push_mode(&"confirmation")
	var stack := modes.snapshot_stack()
	router.world_builder = func(_world: Node3D, _candidate: Dictionary) -> MireTypes.ActionResult:
		return MireTypes.failure(&"fixture_failure", &"Preparation failed.")
	var result: MireTypes.ActionResult = await saves.load_slot(&"manual_1")
	t.check(not result.ok and session.snapshot() == before and router.current_world == world and modes.snapshot_stack() == stack, "R39 failed world preparation preserves state, world and nested menu stack")
	router.world_builder = func(prepared: Node3D, _candidate: Dictionary) -> MireTypes.ActionResult:
		var blocker := ArrivalBlocker.new()
		blocker.position = Vector3(0, 1, 3)
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3, 2, 3)
		collision.shape = box
		blocker.add_child(collision)
		prepared.add_child(blocker)
		return MireTypes.success()
	result = await saves.load_slot(&"manual_1")
	t.check(not result.ok and session.snapshot() == before and router.current_world == world and modes.snapshot_stack() == stack, "R39 failed final arrival returns actual failure and restores prior world/state/menu")
	t.check(not saves.is_loading() and not session.travelling and router.validate_anchor(world, world.entrances[&"entry"]).ok, "R39 failed load releases the operation and retains playable navigation")
	router.world_builder = Callable()
	var identity := player.get_instance_id()
	result = await saves.load_slot(&"manual_1")
	t.check(result.ok and not session.travelling and not saves.is_loading() and router.loaded_scene_id == &"interior_inn", "R39 load success means actual terminal arrival")
	t.check(player.get_instance_id() == identity and player.global_position.distance_to(Vector3(0, 0.06, 3)) < 0.01 and modes.mode == &"gameplay", "R37 successful load uses safe anchor and clears stale modal/input state")
	t.check(saves.save_slot(&"manual_1").ok, "R38 a second manual save keeps a validated backup")
	file = FileAccess.open(saves.slot_path(&"manual_1"), FileAccess.WRITE)
	file.store_string("damaged primary")
	file.close()
	before = session.snapshot()
	t.check((await saves.load_slot(&"manual_1")).code == &"backup_available" and session.snapshot() == before, "R38 a recoverable backup needs explicit selection")
	result = await saves.load_slot(&"manual_1", true)
	t.check(result.ok and result.payload.recovered_backup and FileAccess.get_file_as_string(saves.slot_path(&"manual_1")) == "damaged primary", "R38 explicit backup restores world without silently rewriting primary")

func _ending_failures() -> void:
	var fixture: Script = load("res://tests/unit/test_quests.gd")
	t.check(fixture.ending_checkpoint(session, &"none").ok, "R35 prepare genuine uncommitted ending checkpoint")
	t.check(not saves.continue_without_saving().ok, "R35 no bypass exists before a real ending write failure")
	t.check(session.quests.choose(&"ending", &"charter", &"save/ending").ok, "R35 confirm ending through the actual quest transaction")
	var committed: Dictionary = session.snapshot()
	saves.write_fault = func(stage: StringName) -> bool: return stage == &"replace"
	var failed: MireTypes.ActionResult = saves.retry_autosave()
	t.check(not failed.ok and failed.payload.get("ending_save_failed", false) and not saves.pending_autosave().ending_ready, "R35 failed ending save leaves epilogue gated")
	t.check(session.snapshot() == committed, "R35 failed write retains the committed ending unchanged")
	var notifications: int = _autosaves.size()
	saves._physics_process(0.1)
	t.check(_autosaves.size() == notifications, "R35 failed writes do not retry in an uncontrolled frame loop")
	saves.write_fault = Callable()
	var retried: MireTypes.ActionResult = saves.retry_autosave()
	t.check(retried.ok and retried.payload.get("ending_ready", false) and session.snapshot() == committed, "R35 retry saves without rerunning ending effects")
	t.check(not saves.continue_without_saving().ok, "R35 success cannot be reclassified as an unsaved failure")
	t.check(fixture.ending_checkpoint(session, &"none", &"restitution").ok, "R35 prepare separate genuine ending branch")
	var travel := router.travel(&"interior_inn", &"entry")
	t.check(travel.ok, "R35 place the ending fixture in the actual rest scene")
	var arrival: Array = await router.travel_completed
	t.check(arrival[1].ok, "R35 ending fixture reaches the inn before confirmation")
	t.check(session.quests.choose(&"ending", &"warden", &"save/ending_second").ok, "R35 commit second isolated ending branch")
	saves.write_fault = func(stage: StringName) -> bool: return stage == &"replace"
	failed = saves.retry_autosave()
	t.check(not failed.ok and failed.payload.get("ending_save_failed", false), "R35 induce actual second ending write failure")
	saves.request_autosave(&"rest")
	committed = session.snapshot()
	var bypass: MireTypes.ActionResult = saves.continue_without_saving()
	t.check(bypass.ok and bypass.payload.ending_ready and not bypass.payload.saved and session.snapshot() == committed, "R35 explicit continue unsaved only unlocks presentation")
	t.check(saves.pending_autosave().pending and "rest" in saves.pending_autosave().reasons, "R35 continue unsaved preserves unrelated queued writes")
	t.check(not saves.continue_without_saving().ok, "R35 unsaved confirmation cannot be replayed")
	saves.write_fault = Callable()
	notifications = _autosaves.size()
	saves._physics_process(0.1)
	t.check(_autosaves.size() == notifications, "R35 Continue without saving itself does not retry the failed batch")
	player.spawn_at(Vector3(-4, 0, -2))
	var rested: MireTypes.ActionResult = session.recovery.rest(&"inn_bed", &"save/after_unsaved_rest")
	t.check(rested.ok and rested.payload.get("pending", false), "R39 an actual later rest accepts after continuing unsaved")
	arrival = await router.travel_completed
	t.check(arrival[1].ok and not session.recovery.has_pending_recovery(), "R39 later rest completes its real arrival")
	saves._physics_process(0.1)
	var resumed: MireTypes.ActionResult = saves.inspect_slot(&"autosave")
	t.check(resumed.ok and resumed.payload.snapshot.choices.ending == "warden" and not saves.pending_autosave().pending and _autosaves.size() == notifications + 1, "R39 a new rest request resumes autosaving the committed ending after explicit unsaved continuation")

func _lifecycle() -> void:
	var settings_before: Dictionary = saves.settings.duplicate(true)
	var before: Dictionary = session.snapshot()
	t.check((await saves.start_new_game()).code == &"confirmation_required" and session.snapshot() == before, "R40 existing autosave replacement requires explicit new-game confirmation")
	var manual := FileAccess.get_file_as_string(saves.slot_path(&"manual_1"))
	var bus: Node = t.root.get_node("EventBus")
	var initial: int = bus.choice_committed.get_connections().size()
	for cycle: int in 3:
		t.check(saves.bind_runtime(player, router).ok and bus.choice_committed.get_connections().size() == initial, "R40 repeat runtime bind does not duplicate listeners")
		var started: MireTypes.ActionResult = await saves.start_new_game(true)
		t.check(started.ok and session.state.choices.ending == "none" and session.state.world.is_empty() and session.state.pending_delivery.is_empty(), "R40 new game resets ending, world and rewards through prepared restore")
		t.check(saves.settings == settings_before and FileAccess.get_file_as_string(saves.slot_path(&"manual_1")) == manual, "R40 new game retains settings and every manual save")
		t.check(session.state.inventory.size() == 5 and session.state.player.crowns == 12 and session.state.key_items.is_empty() and session.state.transactions.is_empty(), "R40 new game resets inventory, crowns, evidence and transaction receipts")
		saves._physics_process(0.1)
		saves.request_autosave(&"rest")
		t.check(saves.leave_session().ok and not session.active and not saves.pending_autosave().pending and session.snapshot() == session.fresh_snapshot(), "R40 title cleanup cancels queued writes and resets inactive session")
		t.check(bus.choice_committed.get_connections().size() == initial - 1 and session.quests.autosave_requested.get_connections().is_empty(), "R40 title cleanup disconnects runtime persistence listeners")
		t.check(saves.bind_runtime(player, router).ok, "R40 next title session can rebind existing single player")
	t.check(t.get_nodes_in_group("player").size() == 1, "R40 repeated lifecycle operations do not create duplicate players")

func _on_autosave(reason: StringName, result: MireTypes.ActionResult) -> void:
	_autosaves.append({"reason": reason, "ok": result.ok})
