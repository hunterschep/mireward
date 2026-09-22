extends RefCounted

func run(t: SceneTree) -> void:
	var session: Node = t.root.get_node("GameSession")
	session.new_game()
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	t.root.add_child(player)
	player.set_physics_process(false)
	player.combat.input_driven = false
	var target := TrainingDummy.new()
	t.root.add_child(target)
	target.position = Vector3(0, 0, -1.4)
	var landed: Array[StringName] = []
	target.combat.hit_received.connect(func(request: MireTypes.DamageRequest, result: MireTypes.DamageResult) -> void:
		if result.health_damage > 0:
			landed.append(request.attack_kind)
	)
	var before: Dictionary = session.snapshot()
	t.check(not target.interaction.get_offer(&"player").allowed and target.get_node("Hurtbox").collision_layer == 0, "R47 staged training target has no active interactions or hurtbox")
	t.check(target.activate().ok and target.interaction.interact(&"player", &"training").payload.ui_action == "training", "R47 target opens actual training instructions")
	t.check(before == session.snapshot(), "R47 reading training instructions has no domain effects")
	for kind: StringName in [&"light", &"heavy", &"light"]:
		session.state.player.stamina = 100.0
		t.check(player.combat.request_attack(kind).ok, "R47 actual player attacks training target " + String(kind))
		for frame: int in 90:
			await t.physics_frame
		t.check(target.combat.get_health() == 1000 and not target.combat.dead, "R47 training target remains reusable")
	t.check(landed == [&"light", &"heavy", &"light"], "R47 real spatial light and heavy attacks each strike the straw once")
	t.check(session.state.player.crowns == before.player.crowns and session.state.inventory == before.inventory and session.state.world == before.world and session.state.quests == before.quests and session.state.transactions == before.transactions, "R47 training awards no loot, money, quest progress or receipts")
	target.deactivate()
	t.check(not target.interaction.get_offer(&"player").allowed and target.get_node("Hurtbox").collision_layer == 0, "R47 deactivation removes target from gameplay queries")
	target.free()
	player.free()
	await t.process_frame
	session.new_game()
