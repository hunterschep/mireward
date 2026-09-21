class_name ContentValidation
extends RefCounted

const REQUIRED_IDS := {
	"item": ["rusted_sword", "arming_sword", "falchion", "watchblade", "wooden_buckler", "kite_shield", "patched_coat", "leather_jack", "mail_coat", "bandage", "bread", "tonic", "cart_medicine", "toll_receipt", "orra_charter", "grain_ledger", "rookwatch_seal", "smith_hammer", "ferry_blankets", "hobb_ring", "votive_candle", "ada_badge", "camp_medicine"],
	"enemy": ["cutpurse", "levy_spearman", "deserter_raider", "hollow_keeper", "captain_rusk"],
	"quest": ["mq_01_bread_and_iron", "mq_02_the_kings_due", "mq_03_a_bell_without_rope", "mq_04_names_in_the_ledger", "mq_05_a_debt_in_stone", "mq_06_the_last_toll", "sq_01_a_smiths_hand", "sq_02_a_warm_room", "sq_03_what_the_reeds_keep", "sq_04_three_small_lights", "sq_05_the_broken_badge", "sq_06_no_clean_hands"],
	"dialogue": ["mara_venn", "oswin_pike", "tamsin_reed", "sister_elian", "hobb_fenwick", "ada_vey", "wren_kest", "captain_rusk"],
}

static func registry(rows: Array, kind: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var ids: Dictionary = {}
	for raw: Variant in rows:
		errors.append_array(definition(raw, kind))
		if not raw is Dictionary or not SessionValidation.identifier(raw.get("id")):
			continue
		if ids.has(raw.id):
			errors.append("Duplicate %s ID: %s" % [kind, raw.id])
		ids[raw.id] = true
	return errors

static func definition(raw: Variant, kind: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not raw is Dictionary or not SessionValidation.identifier(raw.get("id")):
		errors.append("%s definition requires a nonempty string ID" % kind)
		return errors
	var label: String = "%s %s" % [kind, raw.id]
	if not SessionValidation.json_safe(raw):
		errors.append("Non-JSON data in " + label)
		return errors
	var text_fields: Array[String] = []
	match kind:
		"item":
			text_fields = ["name_key", "description_key", "icon_path"]
			if raw.get("category") not in ["weapon", "shield", "armor", "consumable", "quest", "evidence"]:
				errors.append("Illegal category in " + label)
			if not nonnegative_integer(raw.get("base_price")) or not positive_integer(raw.get("max_stack")):
				errors.append("Invalid price or stack limit in " + label)
			if raw.get("category") in ["weapon", "shield", "armor"] and raw.get("max_stack") != 1:
				errors.append("Equipment must use single-item stacks in " + label)
			match raw.get("category"):
				"weapon":
					for field: String in ["damage", "stamina", "reach"]:
						if not positive_number(raw.get(field)):
							errors.append("Invalid %s in %s" % [field, label])
					if not raw.get("phases") is Array or raw.phases.size() != 3:
						errors.append("Weapon needs three phase durations in " + label)
					else:
						for phase: Variant in raw.phases:
							if not positive_number(phase):
								errors.append("Invalid weapon phase duration in " + label)
				"shield":
					if not positive_number(raw.get("shield_cost_multiplier")):
						errors.append("Invalid shield cost in " + label)
				"armor":
					if not fraction(raw.get("armor_reduction")):
						errors.append("Invalid armor reduction in " + label)
				"consumable":
					if raw.get("resource") not in ["health", "stamina"] or not positive_number(raw.get("restore_amount")) or not positive_number(raw.get("use_seconds")):
						errors.append("Invalid consumable behavior in " + label)
		"enemy":
			if not positive_integer(raw.get("max_health")) or not fraction(raw.get("armor")) or not nonnegative_integer(raw.get("loot_crowns")):
				errors.append("Invalid health, armor, or loot in " + label)
			for field: String in ["damage", "reach", "windup", "active", "recovery", "walk_speed", "chase_speed", "sight_range", "leash"]:
				if not positive_number(raw.get(field)):
					errors.append("Invalid %s in %s" % [field, label])
			if not SessionValidation.number(raw.get("sight_cos")) or raw.sight_cos < -1 or raw.sight_cos > 1:
				errors.append("Invalid sight cone in " + label)
		"quest":
			if not raw.get("prerequisites") is Array or not raw.get("objectives") is Array or not raw.get("rewards") is Dictionary:
				errors.append("Invalid quest sections in " + label)
			else:
				for prerequisite: Variant in raw.prerequisites:
					if not SessionValidation.identifier(prerequisite):
						errors.append("Invalid quest prerequisite in " + label)
				for objective: Variant in raw.objectives:
					if not objective is Dictionary:
						errors.append("Invalid objective definition in " + label)
		"dialogue":
			text_fields = ["npc_id"]
			if not raw.get("nodes") is Array:
				errors.append("Dialogue nodes must be a list in " + label)
			else:
				for node: Variant in raw.nodes:
					if not node is Dictionary:
						errors.append("Invalid dialogue node in " + label)
		_:
			errors.append("Unknown registry type: " + kind)
	for field: String in text_fields:
		if not SessionValidation.identifier(raw.get(field)):
			errors.append("Missing or invalid %s in %s" % [field, label])
	if raw.has("foundation_only") and not raw.foundation_only is bool:
		errors.append("Invalid foundation marker in " + label)
	return errors

static func validate(db: Node, release: bool = false) -> PackedStringArray:
	var errors: PackedStringArray = db.errors.duplicate()
	for entry: Array in [["items/items", "item", 23], ["enemies/enemies", "enemy", 5], ["quests/quests", "quest", 12], ["dialogue/dialogues", "dialogue", 8]]:
		var rows: Variant = db.read_json("res://data/%s.json" % entry[0])
		if not rows is Array:
			errors.append("Invalid registry: " + str(entry[0]))
			continue
		errors.append_array(registry(rows, entry[1]))
		var present: Dictionary = {}
		for row: Variant in rows:
			if row is Dictionary and SessionValidation.identifier(row.get("id")):
				present[row.id] = true
		for required_id: String in REQUIRED_IDS[entry[1]]:
			if not present.has(required_id):
				errors.append("Missing required %s ID: %s" % [entry[1], required_id])
		if rows.size() != entry[2]:
			errors.append("Wrong content count: " + str(entry[0]))
		if release:
			for row: Variant in rows:
				if row is Dictionary and row.get("foundation_only", false):
					errors.append("Unimplemented content: " + str(row.get("id", "unknown")))
	errors.append_array(world(db.map))
	for shop_id: Variant in db.shops:
		if not SessionValidation.identifier(shop_id) or not db.shops[shop_id] is Dictionary:
			errors.append("Invalid shop: " + str(shop_id))
			continue
		for item_id: Variant in db.shops[shop_id]:
			if not SessionValidation.identifier(item_id) or not db.items.has(StringName(item_id)):
				errors.append("Unknown shop item: " + str(item_id))
			var quantity: Variant = db.shops[shop_id][item_id]
			if not SessionValidation.whole(quantity) or quantity < -1:
				errors.append("Invalid shop stock: " + str(item_id))
	for quest_id: StringName in db.quests:
		for prerequisite: String in db.quests[quest_id].data.prerequisites:
			if not db.quests.has(StringName(prerequisite)):
				errors.append("Unknown quest prerequisite: " + prerequisite)
	if release:
		for item_id: StringName in db.items:
			if not ResourceLoader.exists(db.items[item_id].icon_path):
				errors.append("Missing item icon: " + str(item_id))
	return errors

static func world(map: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not SessionValidation.json_safe(map):
		return PackedStringArray(["World manifest contains non-JSON values."])
	if not map.get("landmarks") is Array or not map.get("spawns") is Array or not map.get("scenes") is Dictionary or not map.get("rest_points") is Dictionary:
		return PackedStringArray(["Missing or invalid world manifest sections."])
	if map.landmarks.size() != 9 or map.spawns.size() != 26:
		errors.append("Expected nine landmarks and 26 hostile spawns.")
	var counts: Dictionary = {"cutpurse": 0, "levy_spearman": 0, "deserter_raider": 0, "hollow_keeper": 0, "captain_rusk": 0}
	var persistent_ids: Dictionary = {}
	for section: String in ["landmarks", "spawns"]:
		for record: Variant in map[section]:
			if not record is Dictionary or not SessionValidation.identifier(record.get("id")) or not SessionValidation.vector(record.get("position")):
				errors.append("Invalid world record in " + section)
				continue
			if persistent_ids.has(record.id):
				errors.append("Duplicate world ID: " + record.id)
			persistent_ids[record.id] = true
			if section == "spawns":
				if not record.get("archetype") is String or not counts.has(record.archetype) or not record.get("scene_id") is String or not map.scenes.has(record.scene_id) or not SessionValidation.identifier(record.get("group")):
					errors.append("Broken spawn reference: " + record.id)
				else:
					counts[record.archetype] += 1
	if counts != {"cutpurse": 7, "levy_spearman": 7, "deserter_raider": 5, "hollow_keeper": 6, "captain_rusk": 1}:
		errors.append("Hostile composition differs from D10.")
	for scene_id: String in ["exterior", "interior_inn", "interior_crypt", "interior_undercroft"]:
		var scene: Variant = map.scenes.get(scene_id)
		if not scene is Dictionary or not scene.get("entrances") is Dictionary or scene.entrances.is_empty() or not SessionValidation.vector(scene.get("safe_anchor")):
			errors.append("Missing scene entrances or safe anchor: " + scene_id)
			continue
		for entrance_id: String in scene.entrances:
			if entrance_id.is_empty() or not SessionValidation.vector(scene.entrances[entrance_id]):
				errors.append("Invalid entrance in scene: " + scene_id)
	for rest_id: String in map.rest_points:
		var rest: Variant = map.rest_points[rest_id]
		if rest_id.is_empty() or not rest is Dictionary or not rest.get("scene_id") is String or not map.scenes.has(rest.scene_id) or not SessionValidation.vector(rest.get("position")):
			errors.append("Invalid rest point: " + rest_id)
	return errors

static func nonnegative_integer(value: Variant) -> bool:
	return SessionValidation.whole(value) and value >= 0

static func positive_integer(value: Variant) -> bool:
	return SessionValidation.whole(value) and value > 0

static func positive_number(value: Variant) -> bool:
	return SessionValidation.number(value) and is_finite(float(value)) and value > 0

static func fraction(value: Variant) -> bool:
	return SessionValidation.number(value) and is_finite(float(value)) and value >= 0 and value < 1
