class_name GameHUD
extends Control

var game: MireGameRoot
var health: ProgressBar
var stamina: ProgressBar
var resources: Label
var weapon: TextureRect
var objective: Label
var compass: Label
var prompt: Label
var target: Label
var target_health: ProgressBar
var healing: Label
var damage: Label
var _weapon_id: String = ""
var _recent_target: StringName = &""
var _recent_left: float = 0.0
var _damage_left: float = 0.0
var _elapsed: float = 0.0

func configure(owner_game: MireGameRoot) -> void:
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stats := VBoxContainer.new()
	stats.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stats.position = Vector2(24, -151)
	stats.custom_minimum_size.x = 280
	add_child(stats)
	var row := HBoxContainer.new()
	stats.add_child(row)
	weapon = TextureRect.new()
	weapon.custom_minimum_size = Vector2(38, 38)
	weapon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	weapon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(weapon)
	resources = UIStyle.label("")
	row.add_child(resources)
	health = _bar(stats)
	stamina = _bar(stats)
	objective = UIStyle.label("")
	objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	objective.position = Vector2(-414, 24)
	objective.size = Vector2(390, 110)
	add_child(objective)
	compass = _center_label(14, 620)
	prompt = _center_label(-104, 720, true)
	healing = _center_label(-66, 720, true)
	target = _center_label(74, 420)
	target_health = ProgressBar.new()
	target_health.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	target_health.position = Vector2(-155, 111)
	target_health.size = Vector2(310, 20)
	target_health.show_percentage = false
	add_child(target_health)
	damage = _center_label(145, 480)
	for label: Node in find_children("*", "Label", true, false):
		UIStyle.outline(label)
	game.player.combat.hit_landed.connect(_hit_landed)
	game.player.combat.hit_received.connect(_hit_received)

func _physics_process(delta: float) -> void:
	if game == null:
		return
	visible = GameSession.active and game.modes.mode == &"gameplay"
	if not visible:
		return
	_recent_left = maxf(0, _recent_left - delta)
	_damage_left = maxf(0, _damage_left - delta)
	damage.visible = _damage_left > 0
	_elapsed += delta
	if _elapsed < 0.1:
		return
	_elapsed = 0
	var player: Dictionary = GameSession.state.player
	health.value = player.health
	health.tooltip_text = "Health %d / 100" % player.health
	stamina.value = player.stamina
	stamina.tooltip_text = "Stamina %d / 100" % player.stamina
	resources.text = "HP %d   ST %d\n%d crowns" % [player.health, player.stamina, player.crowns]
	var stack := GameSession.inventory.find_stack(StringName(GameSession.state.equipment.weapon))
	if not stack.is_empty() and stack.item_id != _weapon_id:
		_weapon_id = stack.item_id
		weapon.texture = load(ContentDB.items[StringName(_weapon_id)].icon_path)
	var tracked := GameSession.quests.tracked_view()
	objective.text = "" if tracked.is_empty() else String(tracked.name) + "\n" + String(tracked.objective.label) + "\n" + String(tracked.objective.location)
	_update_compass(tracked)
	var offer: MireTypes.InteractionOffer = game.interaction.offer
	prompt.text = "" if offer == null else "[" + InputBindings.label(&"interact") + "] " + offer.prompt_key + ("\n" + offer.reason_key if not offer.allowed else "")
	var use := GameSession.recovery.consumption_view()
	healing.text = "" if use.is_empty() else "Using " + ContentDB.items[StringName(use.item_id)].name_key + " · %d%%" % roundi(100 * float(use.elapsed) / float(use.duration))
	_update_target()
	queue_redraw()

func _draw() -> void:
	if visible:
		var center := size / 2
		draw_line(center - Vector2(4, 0), center + Vector2(4, 0), UIStyle.PAPER, 1)
		draw_line(center - Vector2(0, 4), center + Vector2(0, 4), UIStyle.PAPER, 1)

func _update_compass(tracked: Dictionary) -> void:
	var forward: Vector3 = -game.player.camera.global_basis.z
	var angle: float = wrapf(rad_to_deg(atan2(forward.x, -forward.z)), 0, 360)
	var direction: String = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][roundi(angle / 45.0) % 8]
	compass.text = direction + "  ·  %03d°" % roundi(angle)
	if tracked.is_empty():
		return
	var located := NavigationMap.locate_target(game, StringName(tracked.objective.get("hint_target_id", tracked.objective.target_id)))
	if located.is_empty() or located.scene_id != String(game.router.loaded_scene_id):
		return
	var offset: Vector3 = located.position - game.player.global_position
	var local: Vector3 = game.player.global_basis.inverse() * offset
	compass.text += "    " + ("←" if local.x < -3 else "→" if local.x > 3 else "↑" if local.z < 0 else "↓") + "  %dm" % roundi(Vector2(offset.x, offset.z).length())

func _update_target() -> void:
	var victim: CombatComponent
	var origin: Vector3 = game.player.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(origin, origin - game.player.camera.global_basis.z * 24, MireTypes.WORLD | MireTypes.HURTBOX, [game.player.get_node("Hurtbox").get_rid()])
	query.collide_with_areas = true
	var hit := game.player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.get("collider") is CombatHurtbox:
		victim = hit.collider.combat_owner
	if victim == null and _recent_left > 0 and is_instance_valid(game.router.current_world):
		var actor: Node = game.router.current_world.entities.get(_recent_target)
		if is_instance_valid(actor) and actor.get("combat") is CombatComponent:
			victim = actor.combat
	var shown: bool = is_instance_valid(victim) and not victim.dead and victim.faction == &"hostile"
	if shown and victim.entity_id == &"captain_hall_captain_rusk_01":
		shown = victim.actor.has_method("is_duel_active") and bool(victim.actor.call("is_duel_active"))
	target.visible = shown
	target_health.visible = shown
	if shown:
		var name: String = "Captain Rusk" if victim.entity_id == &"captain_hall_captain_rusk_01" else "Hostile"
		if victim.actor is EnemyActor:
			name = String(victim.actor.definition.id).replace("_", " ").capitalize()
		target.text = name
		target_health.max_value = victim.max_health
		target_health.value = victim.get_health()

func _hit_landed(victim_id: StringName, _result: MireTypes.DamageResult) -> void:
	_recent_target = victim_id
	_recent_left = 3.0

func _hit_received(request: MireTypes.DamageRequest, result: MireTypes.DamageResult) -> void:
	if result.health_damage <= 0:
		return
	var local: Vector3 = game.player.global_basis.inverse() * (request.origin - game.player.global_position)
	damage.text = "Hit from " + ("the left" if absf(local.x) > absf(local.z) and local.x < 0 else "the right" if absf(local.x) > absf(local.z) else "ahead" if local.z < 0 else "behind")
	_damage_left = 1.4

func _bar(parent: Node) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(280, 19)
	bar.show_percentage = false
	parent.add_child(bar)
	return bar

func _center_label(y: float, width: float, bottom: bool = false) -> Label:
	var label := UIStyle.label("")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM if bottom else Control.PRESET_CENTER_TOP)
	label.position = Vector2(-width / 2, y)
	label.size = Vector2(width, 45)
	add_child(label)
	return label
