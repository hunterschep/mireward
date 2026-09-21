class_name CombatHurtbox
extends Area3D

var combat_owner: CombatComponent
var radius: float = 0.32
var height: float = 1.6

func configure(component: CombatComponent, capsule_radius: float = 0.32, capsule_height: float = 1.6) -> void:
	combat_owner = component
	radius = capsule_radius
	height = maxf(capsule_height, radius * 2.0)
	collision_layer = MireTypes.HURTBOX
	collision_mask = 0
	monitoring = false
	monitorable = true
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	add_child(collision)

func closest_point(origin: Vector3) -> Vector3:
	var local: Vector3 = to_local(origin)
	var axis := Vector3(0, clampf(local.y, -height * 0.5 + radius, height * 0.5 - radius), 0)
	return to_global(axis + (local - axis).limit_length(radius))
