class_name MeleeSweep
extends RefCounted

const BLADE_RADIUS: float = 0.10
const MAX_ANGLE_STEP: float = 5.0
const MAX_POSITION_STEP: float = 0.10

static func nearest_contact(attacker: CombatComponent, previous: Transform3D, current: Transform3D, from_phase: float, to_phase: float) -> CombatHurtbox:
	if not is_instance_valid(attacker.actor) or not attacker.actor.is_inside_tree():
		return null
	var space := attacker.actor.get_world_3d().direct_space_state
	var reach: float = attacker.attack_profile.reach
	var arc: float = attacker.attack_profile.arc_degrees
	var turn_degrees: float = rad_to_deg(previous.basis.get_rotation_quaternion().angle_to(current.basis.get_rotation_quaternion()))
	var angle_steps: int = ceili((absf(to_phase - from_phase) * arc + turn_degrees) / MAX_ANGLE_STEP)
	var move_steps: int = ceili(previous.origin.distance_to(current.origin) / MAX_POSITION_STEP)
	var steps: int = maxi(1, maxi(angle_steps, move_steps))
	var shape := CapsuleShape3D.new()
	shape.radius = BLADE_RADIUS
	shape.height = reach - BLADE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = MireTypes.HURTBOX
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var nearest: CombatHurtbox
	var nearest_distance: float = INF
	var fractions: Array[float] = []
	for index: int in range(steps + 1):
		fractions.append(float(index) / steps)
	if from_phase < 0.5 and to_phase > 0.5:
		fractions.append((0.5 - from_phase) / (to_phase - from_phase))
	for fraction: float in fractions:
		var transform: Transform3D = previous.interpolate_with(current, fraction)
		var progress: float = lerpf(from_phase, to_phase, fraction)
		var direction: Vector3 = (-transform.basis.z).rotated(transform.basis.y, deg_to_rad(lerpf(-arc * 0.5, arc * 0.5, progress))).normalized()
		query.transform = Transform3D(Basis.looking_at(direction, transform.basis.y) * Basis(Vector3.RIGHT, PI * 0.5), transform.origin + direction * (reach + BLADE_RADIUS) * 0.5)
		for hit: Dictionary in space.intersect_shape(query, 64):
			var collider: Variant = hit.collider
			if not collider is CombatHurtbox:
				continue
			var hurtbox: CombatHurtbox = collider
			if not is_instance_valid(hurtbox.combat_owner) or not attacker.can_hit(hurtbox.combat_owner):
				continue
			var contact: Vector3 = hurtbox.closest_point(transform.origin)
			var distance: float = transform.origin.distance_to(contact)
			if distance > reach + 0.0001 or distance >= nearest_distance:
				continue
			var ray := PhysicsRayQueryParameters3D.create(transform.origin, contact, MireTypes.WORLD)
			ray.hit_from_inside = true
			if not space.intersect_ray(ray).is_empty():
				continue
			ray.to = hurtbox.global_position
			if not space.intersect_ray(ray).is_empty():
				continue
			nearest = hurtbox
			nearest_distance = distance
	return nearest
