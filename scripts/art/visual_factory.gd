class_name VisualFactory
extends RefCounted
## Stateless visual assembly. Combat owns phase progression and damage timing.

static func actor(archetype: StringName) -> Node3D:
	return ArtActors.make(archetype)

static func gear(item_id: StringName) -> Node3D:
	return ArtGear.make(item_id)

static func building(family: StringName) -> Node3D:
	var model := ArtBuildings.make(family)
	ArtMesh.batch(model)
	return model

static func prop(kind: StringName) -> Node3D:
	var model := ArtProps.make(kind)
	# Chest lids remain separate so a world adapter can show opened containers.
	if model.has_node("Lid"):
		var lid := model.get_node("Lid") as Node3D
		model.remove_child(lid)
		ArtMesh.batch(model)
		ArtMesh.batch(lid)
		model.add_child(lid)
	else:
		ArtMesh.batch(model)
	return model

static func pose(model: Node3D, state: StringName, phase: float = 0.0, intensity: float = 1.0) -> void:
	var head := model.get_node("Head") as Node3D
	var left := model.get_node("LeftArm") as Node3D
	var right := model.get_node("RightArm") as Node3D
	var leg_left := model.get_node("LeftLeg") as Node3D
	var leg_right := model.get_node("RightLeg") as Node3D
	model.rotation.x = 0
	model.rotation.z = 0
	head.rotation = Vector3.ZERO
	left.rotation = Vector3(0, 0, -0.07)
	right.rotation = Vector3(0, 0, 0.07)
	leg_left.rotation = Vector3.ZERO
	leg_right.rotation = Vector3.ZERO
	(left.get_node("Elbow") as Node3D).rotation.x = 0
	(right.get_node("Elbow") as Node3D).rotation.x = 0
	var t: float = clampf(phase, 0, 1)
	match state:
		&"idle":
			head.rotation.y = sin(phase * 0.45) * 0.035
			right.rotation.x = sin(phase) * 0.018
		&"walk", &"locomotion":
			leg_left.rotation.x = sin(phase) * 0.45 * intensity
			leg_right.rotation.x = -leg_left.rotation.x
			left.rotation.x = -leg_left.rotation.x * 0.6
			right.rotation.x = leg_left.rotation.x * 0.6
		&"windup":
			right.rotation = Vector3(-1.8 * t, -0.5 * t, 0.5 * t)
			(right.get_node("Elbow") as Node3D).rotation.x = -0.7 * t
			left.rotation.x = -0.35
		&"attack", &"sweep":
			right.rotation = Vector3(lerpf(-1.8, 0.35, t), lerpf(-0.8, 0.8, t), 0.4)
		&"thrust":
			right.rotation = Vector3(-PI / 2, 0, 0)
			(right.get_node("Elbow") as Node3D).rotation.x = lerpf(-0.9, 0.15, t)
		&"block", &"guard":
			left.rotation = Vector3(-0.75, -0.2, -0.2)
			(left.get_node("Elbow") as Node3D).rotation.x = -0.65
			right.rotation.x = -0.5
		&"stagger":
			model.rotation.x = -sin(t * PI) * 0.28
			head.rotation.x = -0.3
			right.rotation.z = 0.5
		&"death":
			model.rotation.z = lerpf(0, PI / 2, t)
			left.rotation.z = -0.5
			right.rotation.z = 0.6
		&"phase_two":
			head.rotation.x = 0.12
			right.rotation = Vector3(-0.95, -0.4, 0.25)
			left.rotation.x = -0.6
			leg_left.rotation.x = -0.16
			leg_right.rotation.x = 0.16

## First-person origin is the grip. Caller owns baseline mount transform.
static func pose_gear(model: Node3D, state: StringName, phase: float = 0.0) -> void:
	model.rotation = Vector3.ZERO
	var t: float = clampf(phase, 0, 1)
	match state:
		&"idle": model.rotation.z = sin(phase) * 0.012
		&"light": model.rotation = Vector3(-sin(t * PI) * 1.25, 0, sin(t * PI) * -0.6)
		&"heavy": model.rotation = Vector3(-sin(t * PI) * 1.8, sin(t * PI) * 0.4, 0)
		&"guard": model.rotation = Vector3(-0.15, -0.2, 0.1)
		&"parry_recoil": model.rotation.x = -sin(t * PI) * 0.5
		&"healing": model.rotation.z = sin(t * PI) * 0.6
