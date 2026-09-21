extends RefCounted

func run(t: SceneTree) -> void:
	var session: Node = t.root.get_node("GameSession")
	var db: Node = t.root.get_node("ContentDB")
	var bus: Node = t.root.get_node("EventBus")
	session.new_game()
	t.check(ContentValidation.validate(db).is_empty(), "R04 canonical content registries")
	var duplicate := [{"id": "same"}, {"id": "same"}]
	t.check(not ContentValidation.registry(duplicate, "enemy").is_empty(), "R04 rejects duplicate IDs")
	var initial: Dictionary = session.snapshot()
	var rolled_back: MireTypes.ActionResult = session.transactions.run(&"failure", func(candidate: Dictionary) -> MireTypes.ActionResult:
		candidate.player.crowns = 999
		return MireTypes.failure(&"fixture", &"Deliberate rollback")
	)
	t.check(not rolled_back.ok and session.state == initial, "R04 failed staged changes do not leak")
	var notifications: Array = []
	var listener := func() -> void: notifications.append(session.state.player.crowns)
	bus.currency_changed.connect(listener)
	var grant := func(candidate: Dictionary) -> MireTypes.ActionResult:
		candidate.player.crowns += 18
		return MireTypes.success({"crowns": 18}).event(&"currency_changed")
	t.check(session.transactions.run(&"failure", grant).ok, "R26 a failed key can retry successfully")
	t.check(session.state.player.crowns == 30 and notifications == [30], "R04 notification observes committed state")
	var replay: MireTypes.ActionResult = session.transactions.run(&"failure", grant)
	t.check(replay.ok and replay.payload.replayed and session.state.player.crowns == 30 and notifications.size() == 1, "R34 receipt replay grants and notifies once")
	bus.currency_changed.disconnect(listener)
	t.check(not bus.currency_changed.is_connected(listener), "R04 listener teardown")
	var malformed: Dictionary = session.snapshot()
	malformed.inventory[0].item_id = "unknown_weapon"
	t.check(not session.restore(malformed).ok and session.state.player.crowns == 30, "R23 rejects unknown IDs without replacing live state")
	malformed = session.snapshot()
	malformed.equipment.armor = "stack_1"
	t.check(not session.restore(malformed).ok, "R23 rejects wrong-slot equipment")
	malformed = session.snapshot()
	malformed.player.crowns = -1
	t.check(not session.restore(malformed).ok, "R23 rejects negative currency")
	session.new_game()
	t.check(session.state.player.crowns == 12 and session.state.inventory.size() == 5 and session.state.transactions.is_empty(), "R23 R40 new game resets starting grants and receipts")
	check_invalid_definitions(t, db)
	check_snapshot_boundary(t, session)
	check_transaction_boundary(t, session)
	check_runner_failures(t)

func check_invalid_definitions(t: SceneTree, db: Node) -> void:
	for kind: String in ["item", "enemy", "quest", "dialogue"]:
		t.check(not ContentValidation.definition({"id": "broken"}, kind).is_empty(), "R04 rejects incomplete " + kind + " before typed construction")
	var item: Dictionary = db.get_item(&"rusted_sword").data.duplicate(true)
	item.phases = [0.2, "fast", 0.5]
	t.check(not ContentValidation.registry([item], "item").is_empty(), "R23 rejects malformed weapon behavior")
	item = db.get_item(&"rusted_sword").data.duplicate(true)
	item.max_stack = 2
	t.check(not ContentValidation.registry([item], "item").is_empty(), "R23 rejects stacked equipment definitions")
	var map: Dictionary = db.map.duplicate(true)
	map.spawns[0].scene_id = "missing_scene"
	t.check(not ContentValidation.world(map).is_empty(), "R04 rejects broken spawn scene reference")
	map = db.map.duplicate(true)
	map.landmarks[1].id = map.landmarks[0].id
	t.check(not ContentValidation.world(map).is_empty(), "R04 rejects duplicate landmark IDs")
	map = db.map.duplicate(true)
	map.scenes.exterior.entrances = {"entry": [0, "floor", 1]}
	t.check(not ContentValidation.world(map).is_empty(), "R04 rejects malformed entrance transforms")
	map = db.map.duplicate(true)
	map.spawns[0].yaw = "north"
	t.check(not ContentValidation.world(map).is_empty(), "R04 rejects nonnumeric spawn facing before actor construction")
	var fixture_path: String = t.test_save_directory.path_join("bad_items.json")
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(JSON.stringify([{"id": "broken"}]))
	file.close()
	var previous_errors: PackedStringArray = db.errors.duplicate()
	var definitions: Dictionary = {}
	db._load_registry(fixture_path, definitions, &"item")
	t.check(definitions.is_empty() and db.errors.size() > previous_errors.size(), "R04 loader rejects incomplete raw data without constructing blank definitions")
	db.errors = previous_errors
	t.check(db.items.size() == 23 and db.enemies.size() == 5, "R23 authoritative item and enemy registries remain intact")

func check_snapshot_boundary(t: SceneTree, session: Node) -> void:
	var initial: Dictionary = session.snapshot()
	var changes: Array[Dictionary] = [
		{"section": "transactions", "key": "broken", "value": {"code": "ok"}},
		{"section": "quests", "key": "unknown", "value": {"state": "ACTIVE", "objectives": {}}},
		{"section": "quests", "key": "mq_01_bread_and_iron", "value": {"state": "NOT_A_STATE", "objectives": {}}},
		{"section": "pending_delivery", "key": "reward", "value": {"item_id": "missing_item", "quantity": 1}},
		{"section": "world", "key": "entity", "value": false},
		{"section": "flags", "key": "puzzle_solved", "value": "yes"},
		{"section": "player", "key": "yaw", "value": INF},
		{"section": "player", "key": "crowns", "value": 1.5}
	]
	for change: Dictionary in changes:
		var malformed: Dictionary = initial.duplicate(true)
		malformed[change.section][change.key] = change.value
		t.check(not session.restore(malformed).ok and session.state == initial, "R04 restore rejects malformed " + change.section + "/" + change.key + " without replacing state")
	var malformed: Dictionary = initial.duplicate(true)
	malformed.shop_stock.oswin_pike.arming_sword = -1
	t.check(not session.restore(malformed).ok, "R26 equipment stock cannot become unlimited")
	malformed = initial.duplicate(true)
	malformed.discoveries = ["missing_landmark"]
	t.check(not session.restore(malformed).ok, "R04 rejects unknown discovery IDs")
	malformed = initial.duplicate(true)
	malformed.next_stack = 1
	t.check(not session.restore(malformed).ok, "R23 rejects stack identity counter collision")
	malformed = initial.duplicate(true)
	malformed.extra = RefCounted.new()
	t.check(not session.restore(malformed).ok, "R04 whole-state boundary rejects live object references")
	malformed = initial.duplicate(true)
	malformed.extra = {&"transient_key": true}
	t.check(not session.restore(malformed).ok, "R04 persisted dictionary keys must be strings")
	t.check(session.validate_snapshot(JSON.parse_string(JSON.stringify(initial))).ok, "R04 canonical snapshot survives JSON numeric decoding")

func check_transaction_boundary(t: SceneTree, session: Node) -> void:
	var initial: Dictionary = session.snapshot()
	t.check(not session.transactions.run(&"invalid_callable", Callable()).ok and not session.transactions.active, "R04 invalid callback fails without retaining lock")
	t.check(not session.transactions.run(&"wrong_result", func(_state: Dictionary) -> int: return 7).ok and not session.transactions.active, "R04 wrong callback result fails without retaining lock")
	t.check(not session.transactions.run(&"null_result", func(_state: Dictionary) -> MireTypes.ActionResult: return null).ok and session.state == initial, "R04 null result rolls back")
	var captured: Array[Dictionary] = []
	var result: MireTypes.ActionResult = session.transactions.run(&"payload_isolation", func(candidate: Dictionary) -> MireTypes.ActionResult:
		captured.append(candidate)
		return MireTypes.success({"stack": candidate.inventory[0]})
	)
	captured[0].inventory[0].quantity = 0
	result.payload.stack.quantity = 0
	t.check(session.state.inventory[0].quantity == 1, "R04 retained stage and result payload cannot mutate committed state")
	var replay: MireTypes.ActionResult = session.transactions.run(&"payload_isolation", Callable())
	t.check(replay.ok and replay.payload.stack.quantity == 1, "R34 receipt replay is detached and does not need the original callback")
	var previous_ledger: Dictionary = session.state.transactions.duplicate(true)
	result = session.transactions.run(&"erase_history", func(candidate: Dictionary) -> MireTypes.ActionResult:
		candidate.transactions.clear()
		return MireTypes.success()
	)
	t.check(not result.ok and session.state.transactions == previous_ledger, "R34 stages cannot erase completed receipts")
	result = session.transactions.run(&"bad_event", func(candidate: Dictionary) -> MireTypes.ActionResult:
		candidate.player.crowns += 10
		return MireTypes.success().event(&"currency_changed", ["unexpected argument"])
	)
	t.check(not result.ok and session.state.player.crowns == initial.player.crowns, "R04 invalid notification refuses the entire transaction")
	var before_invalid: Dictionary = session.snapshot()
	result = session.transactions.run(&"unsafe_receipt", func(candidate: Dictionary) -> MireTypes.ActionResult:
		candidate.player.crowns += 10
		return MireTypes.success({"object": RefCounted.new()})
	)
	t.check(not result.ok and session.state == before_invalid and not session.transactions.active, "R04 validates receipt payload before committing currency")
	session.state.transactions["damaged"] = {"payload": 7}
	result = session.transactions.run(&"damaged", Callable())
	t.check(not result.ok and not session.transactions.active, "R34 damaged live receipt returns an error instead of failing the script")
	session.restore(initial)

func check_runner_failures(t: SceneTree) -> void:
	var fixtures: Dictionary = {
		"assertion": "extends RefCounted\nfunc run(t: SceneTree) -> void:\n\tt.check(false, \"Deliberate assertion failure\")\n",
		"parse": "extends RefCounted\nfunc run(:\n",
		"runtime": "extends RefCounted\nfunc run(_t: SceneTree) -> void:\n\tvar empty: Array = []\n\tprint(empty[0])\n"
	}
	for kind: String in fixtures:
		var path: String = t.test_save_directory.path_join("fixture_" + kind + ".gd")
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(fixtures[kind])
		file.close()
		var output: Array = []
		var status: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/run_all.gd", "--", "--suite=" + path], output, true)
		t.check(status != 0, "R49 runner exits nonzero for " + kind + " failure")
