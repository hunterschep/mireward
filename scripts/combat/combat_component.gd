class_name CombatComponent
extends Node

signal phase_changed(phase: StringName)
signal hit_received(request: MireTypes.DamageRequest, result: MireTypes.DamageResult)
signal hit_landed(victim_id: StringName, result: MireTypes.DamageResult)
signal died(entity_id: StringName)
signal staggered(seconds: float)
signal feedback(outcome: StringName)

const BUFFER_SECONDS: float = 0.12
const PARRY_SECONDS: float = 0.18
const PARRY_COOLDOWN: float = 0.65
const IMMUNITY_SECONDS: float = 0.20
const EPSILON: float = 0.000001
static var next_sequence: int = 0

var actor: Node3D
var player: MirePlayer
var entity_id: StringName
var faction: StringName = &"neutral"
var phase: StringName = &"IDLE"
var phase_elapsed: float = 0.0
var attack_kind: StringName = &"light"
var attack_sequence: int = 0
var attack_profile: Dictionary = {}
var guard_held: bool = false
var dead: bool = false
var health: float = 100.0
var max_health: float = 100.0
var guard_stamina: float = 40.0
var armor: float = 0.0
var shield_multiplier: float = 1.0
var stagger_remaining: float = 0.0
var immunity_remaining: float = 0.0
var input_driven: bool = true
var _profiles: Dictionary = {}
var _clock: float = 0.0
var _guard_started: float = -INF
var _last_parry_start: float = -INF
var _parry_eligible: bool = false
var _buffered: bool = false
var _hit_used: bool = false
var _received_sequences: Dictionary = {}
var _last_transform: Transform3D
var _owns_action_lock: bool = false
var _recoil: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# Damage resolves before later healing completion handlers.
	process_physics_priority = -20

func configure_player(controlled_player: MirePlayer, stable_id: StringName = &"player") -> void:
	actor = controlled_player
	player = controlled_player
	entity_id = stable_id
	faction = &"player"
	player.combat = self
	reset_combat()

func configure_enemy(controlled_actor: Node3D, stable_id: StringName, definition: MireTypes.EnemyDef, source_faction: StringName = &"hostile") -> void:
	actor = controlled_actor
	player = null
	entity_id = stable_id
	faction = source_faction
	max_health = definition.max_health
	health = max_health
	armor = definition.armor
	input_driven = false
	_profiles.clear()
	_profiles[&"light"] = {"damage": float(definition.data.damage), "stamina": 0.0, "windup": float(definition.data.windup), "active": float(definition.data.active), "recovery": float(definition.data.recovery), "reach": float(definition.data.reach), "arc_degrees": 14.0 if definition.id == &"levy_spearman" else 70.0}
	reset_combat()

func set_attack_profile(kind: StringName, profile: Dictionary) -> MireTypes.ActionResult:
	if is_committed():
		return MireTypes.failure(&"busy", &"Finish the current attack before changing its profile.")
	for field: String in ["damage", "windup", "active", "recovery", "reach"]:
		if not profile.has(field) or not (profile[field] is float or profile[field] is int) or not is_finite(float(profile[field])) or float(profile[field]) <= 0:
			return MireTypes.failure(&"invalid_profile", &"Attack values must be positive finite numbers.")
	if kind.is_empty() or float(profile.reach) <= 0.2:
		return MireTypes.failure(&"invalid_profile", &"Attack name and reach are invalid.")
	var saved := profile.duplicate(true)
	saved.stamina = profile.get("stamina", 0.0)
	saved.arc_degrees = profile.get("arc_degrees", 70.0)
	if not (saved.stamina is float or saved.stamina is int) or not is_finite(float(saved.stamina)) or float(saved.stamina) < 0 or not (saved.arc_degrees is float or saved.arc_degrees is int) or not is_finite(float(saved.arc_degrees)) or float(saved.arc_degrees) < 0 or float(saved.arc_degrees) > 120:
		return MireTypes.failure(&"invalid_profile", &"Attack stamina or arc is invalid.")
	_profiles[kind] = saved
	return MireTypes.success()

func request_attack(kind: StringName) -> MireTypes.ActionResult:
	if not _can_act():
		return _refuse(&"unavailable", &"You cannot attack right now.")
	if is_committed():
		if player != null and attack_kind == &"light" and kind == &"light" and phase == &"RECOVERY" and float(attack_profile.recovery) - phase_elapsed <= BUFFER_SECONDS + EPSILON and not _buffered:
			_buffered = true
			return MireTypes.success({"buffered": true})
		return _refuse(&"busy", &"Finish the current attack.")
	if player != null and GameSession.action_locked:
		return _refuse(&"busy", &"Finish the current action.")
	var profile: Dictionary = _get_profile(kind)
	if profile.is_empty():
		return _refuse(&"invalid_attack", &"That attack is not available.")
	var cost: float = float(profile.stamina)
	if cost > 0 and not _spend(cost):
		return _refuse(&"insufficient_stamina", &"Not enough stamina.")
	set_guard(false)
	attack_kind = kind
	attack_profile = profile
	next_sequence += 1
	attack_sequence = next_sequence
	_buffered = false
	_hit_used = false
	phase_elapsed = 0.0
	_last_transform = attack_transform()
	_lock_action(true)
	_set_phase(&"WINDUP")
	return MireTypes.success({"attack_sequence": attack_sequence})

func set_guard(held: bool) -> void:
	if not held:
		guard_held = false
		_parry_eligible = false
		if player != null:
			player.guarding = false
		return
	if guard_held or not _can_act() or is_committed() or (player != null and (GameSession.action_locked or _equipped(&"shield") == null)):
		return
	guard_held = true
	_guard_started = _clock
	_parry_eligible = player != null and _clock - _last_parry_start >= PARRY_COOLDOWN - EPSILON
	if _parry_eligible:
		_last_parry_start = _clock
	if player != null:
		player.guarding = true

func receive_hit(request: MireTypes.DamageRequest) -> MireTypes.DamageResult:
	var ignored := MireTypes.DamageResult.new()
	if entity_id.is_empty() or dead or get_health() <= 0 or not is_instance_valid(actor) or actor.is_queued_for_deletion() or faction == &"neutral" or request == null:
		return ignored
	if request.victim_id != entity_id or request.attacker_id == entity_id or request.attacker_id.is_empty() or request.attack_sequence <= 0 or not is_finite(request.raw_damage) or request.raw_damage <= 0 or not request.origin.is_finite():
		return ignored
	if not _opposed(request.source_faction, faction) or (is_inside_tree() and get_tree().paused):
		return ignored
	if int(_received_sequences.get(request.attacker_id, 0)) >= request.attack_sequence:
		return ignored
	_received_sequences[request.attacker_id] = request.attack_sequence
	if player != null and immunity_remaining > EPSILON:
		return ignored
	var frontal: bool = guard_held and CombatMath.in_guard_cone(-actor.global_basis.z, request.origin - actor.global_position)
	var parry: bool = frontal and _parry_eligible and _clock - _guard_started <= PARRY_SECONDS + EPSILON and get_stamina() >= 5.0
	var defense: float = armor
	var shield: float = shield_multiplier
	if player != null:
		var equipped_armor: MireTypes.ItemDef = _equipped(&"armor")
		var equipped_shield: MireTypes.ItemDef = _equipped(&"shield")
		defense = float(equipped_armor.data.armor_reduction) if equipped_armor != null else 0.0
		shield = float(equipped_shield.data.shield_cost_multiplier) if equipped_shield != null else 1.0
		frontal = frontal and equipped_shield != null
	var result := CombatMath.resolve(request.raw_damage, defense, get_stamina(), frontal, shield, parry, player == null and request.attack_kind == &"heavy")
	if result.stamina_damage > 0:
		_spend(minf(get_stamina(), float(result.stamina_damage)))
	if result.outcome == &"guard_broken":
		apply_stagger(result.stagger_seconds)
	if result.health_damage > 0:
		_set_health(maxf(0.0, get_health() - result.health_damage))
		if player != null:
			immunity_remaining = IMMUNITY_SECONDS
	if get_health() <= 0:
		dead = true
		set_guard(false)
		_buffered = false
		_set_phase(&"DEAD")
		_lock_action(false)
		result.outcome = &"killed"
	_present_outcome(result.outcome)
	if result.health_damage > 0 and not dead:
		AudioService.play_event(&"hurt", actor.global_position)
	hit_received.emit(request, result)
	if dead:
		died.emit(entity_id)
	return result

func apply_stagger(seconds: float) -> void:
	if dead or seconds <= 0:
		return
	set_guard(false)
	_buffered = false
	stagger_remaining = maxf(stagger_remaining, seconds)
	_set_phase(&"STAGGER")
	_lock_action(true)
	staggered.emit(seconds)

func advance(delta: float) -> void:
	if delta <= 0 or not is_finite(delta) or (is_inside_tree() and get_tree().paused) or dead:
		return
	_clock += delta
	immunity_remaining = maxf(0.0, immunity_remaining - delta)
	_recoil = maxf(0.0, _recoil - delta)
	if player == null and not guard_held:
		guard_stamina = minf(40.0, guard_stamina + 10.0 * delta)
	var available: float = delta
	if stagger_remaining > 0:
		available = maxf(0.0, available - stagger_remaining)
		stagger_remaining = maxf(0.0, stagger_remaining - delta)
		if stagger_remaining <= EPSILON:
			stagger_remaining = 0.0
			_set_phase(&"IDLE")
			_lock_action(false)
	while available > EPSILON and is_committed():
		var duration: float = float(attack_profile[String(phase).to_lower()])
		var step: float = minf(available, maxf(0.0, duration - phase_elapsed))
		var before: float = phase_elapsed
		phase_elapsed += step
		available -= step
		if phase == &"ACTIVE" and not _hit_used:
			_sweep(before / duration, phase_elapsed / duration)
		if phase == &"STAGGER" or dead:
			break
		if phase_elapsed + EPSILON >= duration:
			phase_elapsed = 0.0
			match phase:
				&"WINDUP":
					_last_transform = attack_transform()
					_set_phase(&"ACTIVE")
					AudioService.play_event(&"swing", actor.global_position)
				&"ACTIVE": _set_phase(&"RECOVERY")
				&"RECOVERY":
					_set_phase(&"IDLE")
					_lock_action(false)
					if _buffered:
						_buffered = false
						request_attack(&"light")
	_update_pose()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor):
		return
	if player != null and input_driven and player.input_enabled and GameSession.active and not GameSession.travelling:
		set_guard(player.controls.held(&"block"))
		if player.controls.pressed(&"attack_light"):
			request_attack(&"light")
		elif player.controls.pressed(&"attack_heavy"):
			request_attack(&"heavy")
	advance(delta)

func clear_input_edges() -> void:
	_buffered = false
	set_guard(false)

func reset_combat(clear_hit_history: bool = true) -> void:
	clear_input_edges()
	dead = get_health() <= 0
	stagger_remaining = 0.0
	immunity_remaining = 0.0
	phase_elapsed = 0.0
	_clock = 0.0
	_last_parry_start = -INF
	if clear_hit_history:
		_received_sequences.clear()
	_hit_used = false
	guard_stamina = 40.0
	_lock_action(false)
	_set_phase(&"DEAD" if dead else &"IDLE")

func is_committed() -> bool:
	return phase in [&"WINDUP", &"ACTIVE", &"RECOVERY"]

func get_health() -> float:
	return float(GameSession.state.player.health) if player != null else health

func get_stamina() -> float:
	return float(GameSession.state.player.stamina) if player != null else guard_stamina

func can_hit(victim: CombatComponent) -> bool:
	return victim != self and victim.entity_id != entity_id and not victim.dead and victim.get_health() > 0 and is_instance_valid(victim.actor) and not victim.actor.is_queued_for_deletion() and _opposed(faction, victim.faction)

func attack_transform() -> Transform3D:
	if player != null:
		return Transform3D(player.camera.global_basis, player.camera.global_position - Vector3.UP * 0.30)
	return Transform3D(actor.global_basis, actor.global_position + Vector3.UP * 1.1)

func _get_profile(kind: StringName) -> Dictionary:
	if player == null:
		return _profiles.get(kind, {}).duplicate(true)
	if kind not in [&"light", &"heavy"]:
		return {}
	var weapon: MireTypes.ItemDef = _equipped(&"weapon")
	if weapon == null:
		return {}
	var heavy: bool = kind == &"heavy"
	return {"damage": float(weapon.data.damage) * (1.6 if heavy else 1.0), "stamina": float(ceili(float(weapon.data.stamina) * 1.8)) if heavy else float(weapon.data.stamina), "windup": 0.60 if heavy else float(weapon.data.phases[0]), "active": 0.16 if heavy else float(weapon.data.phases[1]), "recovery": 0.64 if heavy else float(weapon.data.phases[2]), "reach": float(weapon.data.reach), "arc_degrees": 85.0 if heavy else 70.0}

func _equipped(slot: StringName) -> MireTypes.ItemDef:
	var stack_id: String = GameSession.state.equipment.get(String(slot), "")
	for stack: Dictionary in GameSession.state.inventory:
		if stack.stack_id == stack_id:
			return ContentDB.get_item(StringName(stack.item_id))
	return null

func _spend(amount: float) -> bool:
	if player != null:
		return player.vitals.spend_stamina(amount)
	if guard_stamina < amount:
		return false
	guard_stamina -= amount
	return true

func _set_health(value: float) -> void:
	if player != null:
		GameSession.state.player.health = value
	else:
		health = value

func _can_act() -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and not entity_id.is_empty() and faction != &"neutral" and not dead and get_health() > 0 and stagger_remaining <= EPSILON and (not is_inside_tree() or not get_tree().paused) and (player == null or (player.input_enabled and GameSession.active and not GameSession.travelling))

func _set_phase(value: StringName) -> void:
	phase = value
	phase_changed.emit(phase)

func _lock_action(locked: bool) -> void:
	if player == null:
		return
	if locked:
		_owns_action_lock = true
		GameSession.action_locked = true
	elif _owns_action_lock:
		_owns_action_lock = false
		GameSession.action_locked = false

func _sweep(from_progress: float, to_progress: float) -> void:
	var current := attack_transform()
	var target: CombatHurtbox = MeleeSweep.nearest_contact(self, _last_transform, current, from_progress, to_progress)
	_last_transform = current
	if target == null:
		return
	_hit_used = true
	var victim: CombatComponent = target.combat_owner
	var request := MireTypes.DamageRequest.new(entity_id, attack_sequence, victim.entity_id, float(attack_profile.damage), attack_kind, actor.global_position, faction)
	var result: MireTypes.DamageResult = victim.receive_hit(request)
	if result.outcome == &"parried":
		apply_stagger(result.stagger_seconds)
	hit_landed.emit(victim.entity_id, result)
	if result.outcome != &"ignored":
		_present_outcome(result.outcome, false)

func _present_outcome(outcome: StringName, play_sound: bool = true) -> void:
	feedback.emit(outcome)
	var sound: StringName = {&"hit": &"metal_impact", &"blocked": &"shield_block", &"parried": &"parry", &"guard_broken": &"guard_break", &"killed": &"death"}.get(outcome, &"")
	if play_sound and not sound.is_empty():
		AudioService.play_event(sound, actor.global_position)
	_recoil = 0.22 if outcome == &"parried" else 0.12

func _update_pose() -> void:
	if player == null or not is_instance_valid(player.gear):
		return
	if GameSession.action_locked and not _owns_action_lock:
		return
	if _recoil > 0:
		player.gear.pose(&"parry_recoil", 1.0 - _recoil / 0.22)
	elif is_committed():
		var fraction: float = phase_elapsed / float(attack_profile[String(phase).to_lower()])
		var progress: float = fraction * 0.4 if phase == &"WINDUP" else (0.4 + fraction * 0.35 if phase == &"ACTIVE" else 0.75 + fraction * 0.25)
		player.gear.pose(&"heavy" if attack_kind == &"heavy" else &"light", progress)
	else:
		player.gear.pose(&"guard" if guard_held else &"idle", _clock)

func _refuse(code: StringName, message: StringName) -> MireTypes.ActionResult:
	if player != null:
		EventBus.feedback.emit(String(message))
	return MireTypes.failure(code, message)

static func _opposed(source: StringName, target: StringName) -> bool:
	return (source == &"player" and target == &"hostile") or (source == &"hostile" and target == &"player")

func _exit_tree() -> void:
	_lock_action(false)
