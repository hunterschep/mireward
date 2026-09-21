class_name CombatDummy
extends Node3D

@export var entity_id: StringName = &"combat_fixture"
@export var archetype: StringName = &"cutpurse"
@export var attacks_player: bool = false
var combat: CombatComponent
var model: Node3D
var _clock: float = 0.0
var _death_time: float = 0.0

func _ready() -> void:
	model = VisualFactory.actor(archetype)
	add_child(model)
	combat = CombatComponent.new()
	add_child(combat)
	combat.configure_enemy(self, entity_id, ContentDB.get_enemy(archetype))
	var hurtbox := CombatHurtbox.new()
	hurtbox.position.y = 0.9
	hurtbox.configure(combat)
	add_child(hurtbox)

func _physics_process(delta: float) -> void:
	_clock += delta
	if combat.dead:
		_death_time = minf(1.0, _death_time + delta * 2)
		VisualFactory.pose(model, &"death", _death_time)
		return
	if combat.phase == &"STAGGER":
		VisualFactory.pose(model, &"stagger", 0.5)
	elif combat.is_committed():
		var progress: float = combat.phase_elapsed / float(combat.attack_profile[String(combat.phase).to_lower()])
		var pose: StringName = &"windup" if combat.phase == &"WINDUP" else (&"attack" if combat.phase == &"ACTIVE" else &"idle")
		VisualFactory.pose(model, pose, progress)
	else:
		VisualFactory.pose(model, &"guard" if combat.guard_held else &"idle", _clock)
	if attacks_player and _clock >= 2.4 and not combat.is_committed() and combat.stagger_remaining <= 0:
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player != null and global_position.distance_to(player.global_position) <= 3.0:
			look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
			combat.request_attack(&"light")
		_clock = 0.0
