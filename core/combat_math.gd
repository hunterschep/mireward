class_name CombatMath
extends RefCounted

static func in_guard_cone(forward: Vector3, to_attacker: Vector3) -> bool:
	var facing := Vector3(forward.x, 0.0, forward.z).normalized()
	var incoming := Vector3(to_attacker.x, 0.0, to_attacker.z).normalized()
	return facing.dot(incoming) >= 0.5 - 0.000001

static func resolve(raw_damage: float, armor: float, stamina: float, frontal_guard: bool, shield_multiplier: float = 1.0, perfect_parry: bool = false, heavy_against_enemy_guard: bool = false) -> MireTypes.DamageResult:
	var result := MireTypes.DamageResult.new()
	if not is_finite(raw_damage) or raw_damage <= 0:
		return result
	var pass_through: float = 1.0
	result.outcome = &"hit"
	if frontal_guard:
		if perfect_parry and stamina >= 5.0:
			result.outcome = &"parried"
			result.stamina_damage = 5
			result.stagger_seconds = 0.65
			return result
		var heavy_multiplier := 1.5 if heavy_against_enemy_guard else 1.0
		var cost := ceili(raw_damage * 0.8 * shield_multiplier * heavy_multiplier)
		if stamina >= cost:
			result.outcome = &"blocked"
			result.stamina_damage = cost
			pass_through = 0.1
		else:
			result.outcome = &"guard_broken"
			result.stamina_damage = ceili(stamina)
			result.stagger_seconds = 0.9
			pass_through = 0.5
	result.health_damage = maxi(1, roundi(raw_damage * pass_through * (1.0 - armor)))
	return result
