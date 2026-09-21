class_name EncounterCoordinator
extends Node

signal danger_changed(danger: bool)
signal windup_started(entity_id: StringName, combat_time: float)

const MAX_THINKING: int = 12
const SLEEP_DISTANCE: float = 70.0
const START_SEPARATION: float = 0.25

var player: MirePlayer
var active_count: int = 0
var reservation_count: int = 0
var _actors: Dictionary = {}
var _active: Dictionary = {}
var _reservations: Dictionary = {}
var _clock: float = 0.0
var _last_start: float = -INF
var _budget_elapsed: float = 0.25
var _danger: bool = false
var _player_combat: CombatComponent

func _ready() -> void:
	process_physics_priority = -40
	process_mode = Node.PROCESS_MODE_PAUSABLE

func configure(controlled_player: MirePlayer) -> void:
	if is_instance_valid(_player_combat) and _player_combat.phase_changed.is_connected(_on_player_phase):
		_player_combat.phase_changed.disconnect(_on_player_phase)
	player = controlled_player
	_player_combat = player.combat if is_instance_valid(player) and player.combat is CombatComponent else null
	if _player_combat != null:
		_player_combat.phase_changed.connect(_on_player_phase)
	_budget_elapsed = 0.25

func register_enemy(actor: EnemyActor) -> MireTypes.ActionResult:
	if actor.entity_id.is_empty():
		return MireTypes.failure(&"invalid_entity", &"An enemy needs a stable identity.")
	if _actors.has(actor.entity_id) and is_instance_valid(_actors[actor.entity_id].get_ref()):
		return MireTypes.failure(&"duplicate_entity", &"That enemy already exists in the world.")
	_actors[actor.entity_id] = weakref(actor)
	_budget_elapsed = 0.25
	return MireTypes.success()

func unregister_enemy(entity_id: StringName) -> void:
	release_attack(entity_id)
	_actors.erase(entity_id)
	_active.erase(entity_id)
	active_count = _active.size()

func reserve_attack(actor: EnemyActor) -> bool:
	_cleanup_reservations()
	if not _active.has(actor.entity_id) or not actor.is_alive_hostile() or _reservations.has(actor.entity_id) or _reservations.size() >= 2 or _clock - _last_start < START_SEPARATION - 0.00001:
		return false
	var data: Dictionary = actor.definition.data
	_reservations[actor.entity_id] = _clock + float(data.windup) + float(data.active) + float(data.recovery) + 0.75
	_last_start = _clock
	reservation_count = _reservations.size()
	windup_started.emit(actor.entity_id, _clock)
	return true

func release_attack(entity_id: StringName) -> void:
	_reservations.erase(entity_id)
	reservation_count = _reservations.size()

func emit_noise(origin: Vector3, source_id: StringName = &"player") -> void:
	if not origin.is_finite():
		return
	for actor: EnemyActor in actors():
		if actor.entity_id != source_id and actor.is_alive_hostile() and actor.can_hear(origin):
			actor.alert_to_player()

func is_dangerous() -> bool:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return false
	for actor: EnemyActor in actors():
		if actor.is_alive_hostile() and (actor.is_engaged() or (actor.global_position.distance_to(player.global_position) <= 15.0 and actor.has_player_line_of_sight())):
			return true
	return false

func actors() -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	for id: StringName in _actors.keys():
		var actor: Variant = _actors[id].get_ref()
		if actor is EnemyActor and not actor.is_queued_for_deletion():
			result.append(actor)
		else:
			unregister_enemy(id)
	return result

func refresh_budget() -> void:
	var candidates: Array[EnemyActor] = []
	var all_actors: Array[EnemyActor] = actors()
	if GameSession.active and not GameSession.travelling and is_instance_valid(player) and player.is_inside_tree():
		for actor: EnemyActor in all_actors:
			if actor.is_alive_hostile() and actor.global_position.distance_to(player.global_position) <= SLEEP_DISTANCE:
				candidates.append(actor)
		candidates.sort_custom(func(first: EnemyActor, second: EnemyActor) -> bool:
			var first_distance: float = first.global_position.distance_squared_to(player.global_position)
			var second_distance: float = second.global_position.distance_squared_to(player.global_position)
			return first_distance < second_distance if not is_equal_approx(first_distance, second_distance) else String(first.entity_id) < String(second.entity_id)
		)
	_active.clear()
	for index: int in mini(MAX_THINKING, candidates.size()):
		_active[candidates[index].entity_id] = true
	for actor: EnemyActor in all_actors:
		actor.set_thinking(_active.has(actor.entity_id))
	active_count = _active.size()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		player = null
		_player_combat = null
		for actor: EnemyActor in actors():
			if actor.player != null:
				actor.detach_player()
	_clock += delta
	_budget_elapsed += delta
	_cleanup_reservations()
	if _budget_elapsed >= 0.25 or not GameSession.active or GameSession.travelling:
		_budget_elapsed = 0.0
		refresh_budget()
	var current_danger: bool = is_dangerous()
	if current_danger != _danger:
		_danger = current_danger
		danger_changed.emit(_danger)

func _cleanup_reservations() -> void:
	for id: StringName in _reservations.keys():
		var actor: Variant = _actors[id].get_ref() if _actors.has(id) else null
		if not actor is EnemyActor or not actor.is_alive_hostile() or float(_reservations[id]) <= _clock:
			release_attack(id)

func _on_player_phase(phase: StringName) -> void:
	if phase == &"ACTIVE" and is_instance_valid(player):
		emit_noise(player.global_position)

func _exit_tree() -> void:
	if is_instance_valid(_player_combat) and _player_combat.phase_changed.is_connected(_on_player_phase):
		_player_combat.phase_changed.disconnect(_on_player_phase)
	for actor: EnemyActor in actors():
		actor.detach_player()
	_actors.clear()
	_active.clear()
	_reservations.clear()
