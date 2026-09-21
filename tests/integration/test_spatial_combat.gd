extends RefCounted

func frames(t: SceneTree, count: int) -> void:
	for index: int in count:
		await t.physics_frame
	await t.process_frame

func target(arena: Node3D, id: StringName, at: Vector3, faction: StringName = &"hostile", archetype: StringName = &"cutpurse") -> CombatComponent:
	var body := Node3D.new()
	body.position = at
	arena.add_child(body)
	var combat := CombatComponent.new()
	body.add_child(combat)
	combat.configure_enemy(body, id, arena.get_tree().root.get_node("ContentDB").get_enemy(archetype), faction)
	combat.set_physics_process(false)
	var hurtbox := CombatHurtbox.new()
	hurtbox.position.y = 0.9
	hurtbox.configure(combat)
	body.add_child(hurtbox)
	return combat

func attack(t: SceneTree, component: CombatComponent, kind: StringName = &"light") -> void:
	var session: Node = t.root.get_node("GameSession")
	session.state.player.stamina = 100.0
	var result: MireTypes.ActionResult = component.request_attack(kind)
	t.check(result.ok, "R13 spatial fixture attack starts")
	await frames(t, 90 if kind == &"heavy" else 55)

func run(t: SceneTree) -> void:
	var session: Node = t.root.get_node("GameSession")
	session.new_game()
	var arena := Node3D.new()
	t.root.add_child(arena)
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	arena.add_child(player)
	player.set_physics_process(false)
	var combat: CombatComponent = player.get_node("Combat")
	combat.input_driven = false
	var near: CombatComponent = target(arena, &"near", Vector3(0, 0, -1.15))
	var far: CombatComponent = target(arena, &"far", Vector3(0, 0, -1.8))
	await frames(t, 3)
	combat.request_attack(&"light")
	await frames(t, 10)
	t.check(near.health == 45.0 and far.health == 45.0 and combat.phase == &"WINDUP", "R12/R13 real physics windup deals no damage")
	await frames(t, 45)
	t.check(near.health == 27.0 and far.health == 45.0, "R13 nearest swept contact is the only victim across active frames")
	await frames(t, 20)
	t.check(near.health == 27.0, "R13 idle and repeated contact never repeat a completed swing")
	near.actor.position = Vector3(-5, 0, -1)
	far.actor.position = Vector3(5, 0, -1)
	var outside: CombatComponent = target(arena, &"outside", Vector3(0, 0, -2.321))
	await frames(t, 3)
	await attack(t, combat)
	t.check(outside.health == 45.0, "R13 hurtbox surface 1 mm beyond two-meter reach cannot be hit")
	outside.actor.position.z = -2.319
	await frames(t, 3)
	await attack(t, combat)
	t.check(outside.health == 27.0, "R13 hurtbox surface 1 mm inside two-meter reach can be hit")
	outside.actor.position = Vector3(5, 0, -5)
	var behind: CombatComponent = target(arena, &"behind_wall", Vector3(0, 0, -1.8))
	var wall := StaticBody3D.new()
	wall.collision_layer = MireTypes.WORLD
	wall.position = Vector3(0, 1.0, -0.8)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 3, 0.1)
	collision.shape = shape
	wall.add_child(collision)
	arena.add_child(wall)
	await frames(t, 3)
	await attack(t, combat)
	t.check(behind.health == 45.0, "R13 closed world wall occludes a weapon overlapping victim")
	behind.actor.position.z = -1.05
	await frames(t, 3)
	await attack(t, combat)
	t.check(behind.health == 45.0, "R13 wall blocks an actor even if hurtbox surface protrudes in front")
	wall.queue_free()
	await frames(t, 3)
	await attack(t, combat)
	t.check(behind.health == 27.0, "R13 same target becomes hittable after removing the world barrier")
	behind.actor.position = Vector3(5, 0, -4)
	var neutral: CombatComponent = target(arena, &"neutral", Vector3(0, 0, -0.8), &"neutral")
	var eligible: CombatComponent = target(arena, &"eligible", Vector3(0, 0, -1.6))
	await frames(t, 3)
	await attack(t, combat)
	t.check(neutral.health == 45.0 and eligible.health == 27.0 and session.state.player.health == 100.0, "R13 neutral and self hurtboxes are skipped without consuming hostile swing")
	eligible.health = 0.0
	eligible.dead = true
	await attack(t, combat)
	t.check(eligible.health == 0.0 and neutral.health == 45.0, "R13 dead victims reject later active sweeps")
	neutral.actor.position = Vector3(5, 0, -3)
	eligible.actor.position = Vector3(5, 0, -2)
	var heavy_target: CombatComponent = target(arena, &"heavy_target", Vector3(0, 0, -1.5))
	await frames(t, 3)
	await attack(t, combat, &"heavy")
	t.check(heavy_target.health == 16.0, "R16 actual heavy contact deals round(18 x 1.6) once, not twice")
	heavy_target.actor.position = Vector3(5, 0, 0)
	var attacking_enemy: CombatComponent = target(arena, &"attacking_enemy", Vector3(0, 0, -1.3))
	attacking_enemy.actor.rotation.y = PI
	attacking_enemy.set_physics_process(true)
	await frames(t, 3)
	attacking_enemy.request_attack(&"light")
	await frames(t, 60)
	t.check(session.state.player.health == 88.0, "R13 opposing enemy sweep actually reaches the player's hurtbox")
	await frames(t, 35)
	session.state.player.health = 100.0
	combat.reset_combat()
	attacking_enemy.request_attack(&"light")
	await frames(t, 24)
	combat.set_guard(true)
	await frames(t, 12)
	t.check(session.state.player.health == 100.0 and combat.get_stamina() == 100.0 - 29.0 - 5.0 and attacking_enemy.phase == &"STAGGER", "R15 actual contact perfect-parries and staggers attacking component")
	await frames(t, 45)
	t.check(attacking_enemy.phase == &"IDLE", "R15 actual parried enemy returns from stagger without later damage")
	attacking_enemy.actor.position = Vector3(5, 0, 2)
	combat.set_guard(false)
	var paused_target: CombatComponent = target(arena, &"paused_target", Vector3(0, 0, -1.4))
	session.state.player.stamina = 100.0
	combat.request_attack(&"light")
	await frames(t, 18)
	var saved_phase: StringName = combat.phase
	var saved_elapsed: float = combat.phase_elapsed
	var saved_health: float = paused_target.health
	var saved_sequence: int = combat.attack_sequence
	t.paused = true
	await t.create_timer(0.1, true, false, true).timeout
	t.check(combat.phase == saved_phase and combat.phase_elapsed == saved_elapsed and paused_target.health == saved_health, "R12 real paused scene freezes attack and damage processing")
	t.paused = false
	await frames(t, 40)
	t.check(paused_target.health == 27.0 and combat.attack_sequence == saved_sequence, "R13 resume retains single-victim damage ledger and original attack")
	paused_target.actor.position = Vector3(5, 0, 4)
	var turn_target: CombatComponent = target(arena, &"turn_target", Vector3(0, 0, -1.7))
	player.rotation.y = deg_to_rad(-80.0)
	session.state.player.stamina = 100.0
	combat.request_attack(&"light")
	await frames(t, 15)
	player.rotation.y = deg_to_rad(80.0)
	await frames(t, 1)
	t.check(turn_target.health == 27.0, "R13 rapid active-phase rotation sweeps through intermediate directions")
	await frames(t, 45)
	player.rotation.y = 0.0
	var modes := GameModeController.new()
	arena.add_child(modes)
	modes.configure(player)
	combat.input_driven = true
	player.controls.tick()
	Input.action_press(&"attack_light")
	await frames(t, 3)
	modes.push_mode(&"pause")
	var interrupted_sequence: int = combat.attack_sequence
	modes.pop_mode()
	await frames(t, 60)
	t.check(combat.attack_sequence == interrupted_sequence, "R12/R08 holding attack through a modal does not create a fresh attack")
	Input.action_release(&"attack_light")
	player.controls.tick()
	arena.queue_free()
	await t.process_frame
