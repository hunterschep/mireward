extends Node3D

var player: MirePlayer
var modes: GameModeController
var caption: Label

func _ready() -> void:
	GameSession.new_game()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("a8b2aa")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d8ceb1")
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_box(Vector3(24, 1, 24), Vector3(0, -0.5, 0))
	_box(Vector3(4, 2.4, 0.4), Vector3(5, 1.2, -5))
	player = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	player.spawn_at(Vector3.ZERO)
	modes = GameModeController.new()
	add_child(modes)
	modes.configure(player)
	for index: int in 3:
		var dummy: CombatDummy = load("res://scenes/actors/combat_dummy.tscn").instantiate()
		dummy.entity_id = StringName("fixture_%d" % index)
		dummy.archetype = [&"cutpurse", &"levy_spearman", &"deserter_raider"][index]
		dummy.position = [Vector3(0, 0, -2), Vector3(-4, 0, -5), Vector3(5, 0, -6)][index]
		dummy.attacks_player = index == 1
		dummy.rotation.y = PI
		add_child(dummy)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(24, 20)
	caption.add_theme_color_override("font_color", Color("242b28"))
	canvas.add_child(caption)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	canvas.add_child(crosshair)
	player.combat.feedback.connect(_feedback)
	player.combat.died.connect(func(_id: StringName) -> void: modes.push_mode(&"death"))
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tests/output/combat")
		get_viewport().get_texture().get_image().save_png("res://tests/output/combat/arena.png")
		get_tree().quit()

func _process(_delta: float) -> void:
	caption.text = "Melee test arena | Left mouse: light | R: heavy | Right mouse: guard | Escape: pause\nHealth %d | Stamina %d | Phase %s\nLeft spearman attacks on approach. Front cutpurse tests reach; right raider sits behind the wall." % [GameSession.state.player.health, GameSession.state.player.stamina, player.combat.phase]

func _feedback(outcome: StringName) -> void:
	caption.add_theme_color_override("font_color", {&"hit": Color("824d3c"), &"blocked": Color("68736b"), &"parried": Color("e1b978"), &"guard_broken": Color("824d3c"), &"killed": Color("242b28")}.get(outcome, Color("242b28")))

func _box(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = MireTypes.WORLD
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	ArtMesh.box(body, "Stone", size, Vector3.ZERO, "stone")
	add_child(body)
