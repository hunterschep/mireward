class_name CaptainRusk
extends EnemyActor
## Duel decisions reuse EnemyActor movement and the authoritative combat resolver.

signal duel_changed(active: bool)
signal phase_two_started
signal breath_started

const ENTITY_ID: StringName = &"captain_hall_captain_rusk_01"
const PROFILES := {
	&"thrust": {"damage": 24.0, "reach": 2.5, "windup": 0.75, "active": 0.15, "recovery": 0.85, "stamina": 0.0, "arc_degrees": 14.0},
	&"sweep": {"damage": 22.0, "reach": 2.2, "windup": 0.90, "active": 0.20, "recovery": 1.10, "stamina": 0.0, "arc_degrees": 100.0},
}
var interaction: InteractionComponent
var name_label: Label3D
var phase_two: bool = false
var attacks_started: int = 0
var breaths_started: int = 0
var breath_remaining: float = 0.0
var challenge_check: Callable
var _live: bool = false
var _duel_active: bool = false
var _pair_count: int = 0
var _attack_pending: bool = false
var _bound_player_combat: CombatComponent

func supports_archetype(archetype: StringName) -> bool:
	return archetype == &"captain_rusk"

func configure(spawn: Dictionary, controlled_player: MirePlayer, encounter: EncounterCoordinator) -> MireTypes.ActionResult:
	if spawn.get("id") != String(ENTITY_ID):
		return MireTypes.failure(&"invalid_entity", &"The captain needs his canonical encounter identity.")
	var configured := super.configure(spawn, controlled_player, encounter)
	if not configured.ok:
		return configured
	for kind: StringName in PROFILES:
		var installed := combat.set_attack_profile(kind, PROFILES[kind])
		if not installed.ok:
			return installed
	interaction = InteractionComponent.new()
	interaction.name = "CaptainConversation"
	interaction.entity_id = ENTITY_ID
	interaction.action_id = &"talk"
	interaction.kind = "npc"
	interaction.physical_body = self
	interaction.focus_offset = Vector3(0, 1.5, -0.2)
	interaction.offer_handler = _offer
	interaction.action_handler = _talk
	interaction.enabled = false
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	interaction.add_child(collision)
	add_child(interaction)
	name_label = Label3D.new()
	name_label.name = "CaptainName"
	name_label.text = "Captain Rusk"
	name_label.position.y = 2
	name_label.font_size = 28
	name_label.pixel_size = 0.006
	name_label.outline_size = 8
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.visibility_range_end = 24
	add_child(name_label)
	_apply_duel_state()
	return MireTypes.success()

func activate() -> MireTypes.ActionResult:
	if not _configured or not is_inside_tree() or not is_instance_valid(player):
		return MireTypes.failure(&"unavailable", &"The captain's live encounter is not ready.")
	if not _live:
		_bound_player_combat = player.combat
		_bound_player_combat.died.connect(_player_died)
		_live = true
	_apply_duel_state()
	if not combat.dead:
		set_physics_process(true)
	return MireTypes.success()

func deactivate() -> void:
	_live = false
	if is_instance_valid(_bound_player_combat) and _bound_player_combat.died.is_connected(_player_died):
		_bound_player_combat.died.disconnect(_player_died)
	_bound_player_combat = null
	if is_instance_valid(interaction):
		interaction.enabled = false

func challenge() -> MireTypes.ActionResult:
	if not _live or combat.dead or not is_instance_valid(player) or not GameSession.active or GameSession.travelling or GameSession.action_locked or get_tree().paused or float(GameSession.state.player.health) <= 0:
		return MireTypes.failure(&"unavailable", &"The captain cannot be challenged now.")
	if _duel_active:
		return MireTypes.failure(&"already_active", &"The duel is already underway.")
	if not GameSession.state.flags.undercroft_open or GameSession.state.quests[QuestPredicates.MQ05].state not in ["ACTIVE", "READY"] or not GameSession.state.evidence.get("conversation/" + QuestPredicates.MQ05 + "/challenge_rusk", false):
		return MireTypes.failure(&"confirmation_required", &"Speak to Rusk and explicitly choose Challenge Rusk.")
	if player.camera.global_position.distance_to(interaction.focus_position()) > 2.5:
		return MireTypes.failure(&"too_far", &"Move close enough to face the captain.")
	if not challenge_check.is_valid():
		return MireTypes.failure(&"unavailable", &"The captain's arena is not ready.")
	var checked: Variant = challenge_check.call()
	if not checked is MireTypes.ActionResult or not checked.ok:
		return checked if checked is MireTypes.ActionResult else MireTypes.failure(&"invalid_runtime", &"The arena could not be checked.")
	_duel_active = true
	_apply_duel_state()
	_set_state(&"CHASE")
	coordinator.refresh_budget()
	duel_changed.emit(true)
	return MireTypes.success({"entity_id": String(ENTITY_ID), "duel_active": true})

func is_duel_active() -> bool:
	return _duel_active and not combat.dead

func is_alive_hostile() -> bool:
	return _duel_active and super.is_alive_hostile()

func is_engaged() -> bool:
	return is_alive_hostile()

func apply_persistent_state(record: Dictionary) -> MireTypes.ActionResult:
	var result := super.apply_persistent_state(record)
	if result.ok:
		_apply_duel_state()
	return result

func reset_living_encounter() -> MireTypes.ActionResult:
	if combat.dead:
		return MireTypes.failure(&"defeated", &"A defeated captain cannot return.")
	_duel_active = false
	_attack_pending = false
	phase_two = false
	attacks_started = 0
	breaths_started = 0
	_pair_count = 0
	breath_remaining = 0
	var result := super.reset_living_encounter()
	_apply_duel_state()
	if _live:
		duel_changed.emit(false)
	return result

func set_thinking(enabled: bool) -> void:
	super.set_thinking(enabled and _duel_active)
	if _live and not combat.dead:
		set_physics_process(true)

func detach_player() -> void:
	# Temporary tree removal must preserve committed phases for travel rollback.
	if is_instance_valid(coordinator):
		coordinator.release_attack(entity_id)
	thinking = false
	navigation.avoidance_enabled = false
	combat.set_physics_process(false)
	set_physics_process(false)
	player = null
	velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if combat.dead:
		super._physics_process(delta)
		return
	if not _live or GameSession.travelling:
		return
	_clock += delta
	_state_elapsed += delta
	if not _duel_active:
		velocity = Vector3.ZERO
		_update_pose()
		return
	if not _player_available():
		_end_duel()
		return
	if combat.phase == &"STAGGER" or combat.is_committed():
		if combat.phase == &"WINDUP":
			_face(player.global_position, delta, 1.8)
		_stop_movement(delta)
	elif breath_remaining > 0:
		breath_remaining = maxf(0, breath_remaining - delta)
		_set_state(&"BREATH")
		_stop_movement(delta)
	else:
		var kind: StringName = &"thrust" if attacks_started % 2 == 0 else &"sweep"
		var reach: float = float(PROFILES[kind].reach)
		var distance: float = global_position.distance_to(player.global_position)
		_face(player.global_position, delta, 5)
		if distance <= reach + 0.05 and has_player_line_of_sight():
			_stop_movement(delta)
			if CombatMath.in_guard_cone(-global_basis.z, player.global_position - global_position) and coordinator.reserve_attack(self):
				var profile: Dictionary = PROFILES[kind].duplicate(true)
				if phase_two:
					profile.recovery = float(profile.recovery) * 0.85
				var installed := combat.set_attack_profile(kind, profile)
				var attacked := combat.request_attack(kind) if installed.ok else installed
				if attacked.ok:
					attacks_started += 1
					_pair_count += 1
					_attack_pending = true
				else:
					coordinator.release_attack(entity_id)
		else:
			_set_state(&"CHASE")
			_navigate(player.global_position, float(definition.data.chase_speed), delta)
	_update_pose()

func _on_combat_phase(phase: StringName) -> void:
	if not _configured:
		return
	match phase:
		&"WINDUP": _set_state(&"WINDUP")
		&"ACTIVE": _set_state(&"ACTIVE")
		&"RECOVERY": _set_state(&"RECOVER")
		&"STAGGER":
			_set_state(&"STAGGER")
			coordinator.release_attack(entity_id)
		&"IDLE":
			coordinator.release_attack(entity_id)
			if _attack_pending:
				_attack_pending = false
				if _pair_count >= 2:
					_pair_count = 0
					breath_remaining = 0.85
					breaths_started += 1
					breath_started.emit()
			_set_state(&"BREATH" if breath_remaining > 0 else &"CHASE" if _duel_active else &"IDLE")

func _on_hit_received(request: MireTypes.DamageRequest, result: MireTypes.DamageResult) -> void:
	super._on_hit_received(request, result)
	if _duel_active and not combat.dead and not phase_two and combat.health <= 110:
		phase_two = true
		phase_two_started.emit()
		EventBus.feedback.emit(String(ContentDB.dialogues[&"captain_rusk"].data.combat_lines.half_health))

func _on_died(id: StringName) -> void:
	super._on_died(id)
	_end_duel()

func _player_died(_id: StringName) -> void:
	_end_duel()

func _end_duel() -> void:
	var changed: bool = _duel_active
	_duel_active = false
	_attack_pending = false
	breath_remaining = 0
	if not combat.dead:
		combat.reset_combat(false)
		_set_state(&"IDLE")
	_apply_duel_state()
	if changed:
		duel_changed.emit(false)

func _apply_duel_state() -> void:
	if not is_instance_valid(combat):
		return
	combat.faction = &"hostile" if _duel_active else &"neutral"
	collision_layer = 0 if combat.dead else MireTypes.HOSTILE if _duel_active else MireTypes.NEUTRAL
	hurtbox.collision_layer = MireTypes.HURTBOX if _duel_active and not combat.dead else 0
	if is_instance_valid(interaction):
		interaction.enabled = _live and not _duel_active and not combat.dead
	if is_instance_valid(name_label):
		name_label.visible = not _duel_active and not combat.dead

func _offer(actor_id: StringName) -> MireTypes.InteractionOffer:
	var allowed: bool = _live and not _duel_active and not combat.dead and actor_id == &"player" and GameSession.active and not GameSession.travelling and float(GameSession.state.player.health) > 0
	return MireTypes.InteractionOffer.new(ENTITY_ID, "Talk to Captain Rusk", allowed, "The captain cannot speak now." if not allowed else "", &"talk")

func _talk(actor_id: StringName, action_id: StringName) -> MireTypes.ActionResult:
	if action_id != &"talk" or not _offer(actor_id).allowed:
		return MireTypes.failure(&"unavailable", &"The captain cannot speak now.")
	return GameSession.dialogue.start(&"captain_rusk")

func _update_pose() -> void:
	if not is_instance_valid(model) or combat.dead:
		return
	if combat.phase == &"STAGGER":
		VisualFactory.pose(model, &"stagger", 0.5)
	elif combat.is_committed():
		var progress: float = combat.phase_elapsed / float(combat.attack_profile[String(combat.phase).to_lower()])
		var pose: StringName = &"windup" if combat.phase == &"WINDUP" else combat.attack_kind if combat.phase == &"ACTIVE" else &"idle"
		VisualFactory.pose(model, pose, progress)
	elif breath_remaining > 0:
		VisualFactory.pose(model, &"idle", _clock)
		(model.get_node("RightArm") as Node3D).rotation.x = 0.3
		(model.get_node("Head") as Node3D).rotation.x = 0.12
	elif Vector2(velocity.x, velocity.z).length() > 0.2:
		VisualFactory.pose(model, &"walk", _clock * 4)
	else:
		VisualFactory.pose(model, &"phase_two" if phase_two and _duel_active else &"idle", _clock)

func _exit_tree() -> void:
	deactivate()
	super._exit_tree()
