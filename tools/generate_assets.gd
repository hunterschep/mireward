extends SceneTree
## Original deterministic art outputs. Run with the pinned Godot --script flag.

const ROOT := "res://assets/"
var _failed: bool = false

func _initialize() -> void:
	call_deferred("generate")

func generate() -> void:
	for directory: String in ["icons", "textures", "materials", "models/actors", "models/gear", "models/buildings", "models/props"]:
		var err: Error = DirAccess.make_dir_recursive_absolute(ROOT + directory)
		if err != OK:
			_fail(directory, err)
	if _failed:
		quit(1)
		return
	var items: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/items.json"))
	for item: Dictionary in items:
		_write(String(item.icon_path), _icon(String(item.id), String(item.category)))
	_textures()
	for key: String in ArtMesh.PALETTE:
		var err: Error = ResourceSaver.save(ArtMesh.material(key), ROOT + "materials/" + key + ".tres")
		if err != OK:
			_fail("material " + key, err)
		_stable_resource_ids(ROOT + "materials/" + key + ".tres")
	for id: StringName in ArtActors.ARCHETYPES:
		_save(VisualFactory.actor(id), "actors", id)
	for item: Dictionary in items:
		_save(VisualFactory.gear(StringName(item.id)), "gear", StringName(item.id))
	for id: StringName in ArtBuildings.FAMILIES:
		_save(VisualFactory.building(id), "buildings", id)
	for id: StringName in ArtProps.KINDS:
		_save(VisualFactory.prop(id), "props", id)
	if _failed:
		quit(1)
		return
	print("Generated 23 icons, 5 textures, %d materials, %d actors, %d gear, %d buildings, %d props." % [ArtMesh.PALETTE.size(), ArtActors.ARCHETYPES.size(), items.size(), ArtBuildings.FAMILIES.size(), ArtProps.KINDS.size()])
	quit(0)

func _save(node: Node3D, category: String, id: StringName) -> void:
	ArtMesh.own_tree(node, node)
	var scene := PackedScene.new()
	var packed: Error = scene.pack(node)
	if packed != OK:
		_fail(String(id), packed)
		node.free()
		return
	var saved: Error = ResourceSaver.save(scene, ROOT + "models/" + category + "/" + String(id) + ".tscn", ResourceSaver.FLAG_RELATIVE_PATHS)
	if saved != OK:
		_fail(String(id), saved)
		node.free()
		return
	_stable_resource_ids(ROOT + "models/" + category + "/" + String(id) + ".tscn")
	node.free()

func _stable_resource_ids(path: String) -> void:
	var contents: String = FileAccess.get_file_as_string(path)
	var pattern := RegEx.new()
	pattern.compile('^\\[(?:sub_resource|ext_resource) .*id="([^"]+)"', true)
	var index: int = 0
	for line: String in contents.split("\n"):
		var found: RegExMatch = pattern.search(line)
		if found != null:
			index += 1
			contents = contents.replace('"' + found.get_string(1) + '"', '"asset_%03d"' % index)
	_write(path, contents)

func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail(path, FileAccess.get_open_error())
		return
	file.store_string(contents)
	if file.get_error() != OK:
		_fail(path, file.get_error())

func _fail(path: String, error: Error) -> void:
	printerr("Asset generation failed: %s (%s)" % [path, error_string(error)])
	_failed = true

func _textures() -> void:
	for kind: String in ["stone", "timber", "linen", "parchment", "palette"]:
		var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
		for y: int in 128:
			for x: int in 128:
				var color: Color
				if kind == "palette":
					var names: Array = ArtMesh.PALETTE.keys()
					color = Color(ArtMesh.PALETTE[names[mini(names.size() - 1, (y / 32) * 5 + x / 26)]])
				else:
					color = Color(ArtMesh.PALETTE[kind])
					var grain: float = float((x * 73 + y * 19 + (x * y) % 31) % 11 - 5) / 255.0
					if kind == "stone" and (y % 32 < 2 or (x + (y / 32) % 2 * 32) % 64 < 2):
						grain = -0.08
					elif kind == "timber" and (x % 32 < 2 or (x * 7 + y / 8) % 29 == 0):
						grain = -0.045
					elif kind == "linen":
						grain = 0.018 if (x + y) % 2 == 0 else -0.018
					color = Color(color.r + grain, color.g + grain, color.b + grain)
				image.set_pixel(x, y, color)
		var err: Error = image.save_png(ROOT + "textures/" + kind + ".png")
		if err != OK:
			_fail(kind, err)
		var import_path: String = ROOT + "textures/" + kind + ".png.import"
		if FileAccess.file_exists(import_path):
			_write(import_path, FileAccess.get_file_as_string(import_path).replace("mipmaps/generate=false", "mipmaps/generate=true"))

func _icon(id: String, category: String) -> String:
	var art: String = ""
	var ink := "#242b28"
	var metal := "#a8b2aa"
	var warm := "#e1b978"
	match category:
		"weapon":
			var blade: String = "M47 81L81 19L89 12L90 27L56 86Z"
			if id == "falchion":
				blade = "M46 80L76 23L96 10L92 40L57 86Z"
			art = '<path d="%s" fill="%s"/><path d="M51 77L83 23" stroke="#68736b" stroke-width="3"/><path d="M36 73L65 91M49 86L39 105" stroke="%s" stroke-width="7"/><circle cx="36" cy="109" r="5" fill="%s"/>' % [blade, "#a58a6a" if id == "rusted_sword" else metal, warm if id == "watchblade" else "#824d3c", warm]
		"shield":
			if id == "kite_shield":
				art = '<path d="M27 31L64 18L101 31L94 77L64 111L34 77Z" fill="#a8b2aa"/><path d="M34 36L64 25L94 36L87 73L64 100L41 73Z" fill="#824d3c"/><path d="M64 30V88M44 53H84" stroke="#d8ceb1" stroke-width="9"/>'
			else:
				art = '<circle cx="64" cy="64" r="43" fill="#7b8881"/><circle cx="64" cy="64" r="36" fill="#574939"/><path d="M46 34V94M64 29V100M82 34V94" stroke="#3b352d" stroke-width="3"/><circle cx="64" cy="64" r="14" fill="#a8b2aa"/>'
		"armor":
			var coat: String = "#ada68d" if id == "patched_coat" else ("#574939" if id == "leather_jack" else "#7b8881")
			art = '<path d="M43 22L30 29L16 58L33 67L39 55L35 106H93L89 55L95 67L112 58L98 29L85 22L75 32H53Z" fill="%s"/><path d="M38 79H91" stroke="#3b352d" stroke-width="8"/><path d="M58 76H70V84H58Z" fill="#e1b978"/>' % coat
			if id == "mail_coat":
				for y: int in range(42, 73, 9):
					art += '<path d="M44 %dH84" stroke="#444e4c" stroke-width="3" stroke-dasharray="4 4"/>' % y
			elif id == "patched_coat":
				art += '<path d="M70 47H84V66H70Z" fill="#824d3c"/>'
		_:
			art = _object_icon(id, ink, metal, warm)
	return '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><rect x="3" y="3" width="122" height="122" rx="15" fill="#242b28"/><path d="M18 10H110L118 18V110L110 118H18L10 110V18Z" fill="none" stroke="#68736b" stroke-width="2"/>%s</svg>\n' % art

func _object_icon(id: String, ink: String, metal: String, warm: String) -> String:
	match id:
		"tonic", "cart_medicine", "camp_medicine":
			var bottle: String = "#777844" if id == "tonic" else "#824d3c"
			return '<path d="M51 23H77V47L92 60V104H36V60L51 47Z" fill="%s"/><rect x="51" y="17" width="26" height="13" rx="2" fill="#574939"/><rect x="42" y="63" width="44" height="28" fill="#d8ceb1"/><path d="M52 77H76M64 67V87" stroke="#824d3c" stroke-width="5"/>' % bottle
		"bread": return '<path d="M22 76Q16 48 48 37L78 32Q104 40 109 61L105 83L64 102L29 94Z" fill="#a38a51"/><path d="M39 53L52 75M60 44L73 66M81 40L94 59" stroke="#e1b978" stroke-width="7"/>'
		"bandage": return '<path d="M39 30H88V99H39Z" fill="#d8ceb1"/><ellipse cx="64" cy="30" rx="25" ry="12" fill="#ada68d"/><ellipse cx="64" cy="30" rx="10" ry="5" fill="#574939"/><path d="M40 47L88 64M40 67L88 84M40 87L70 98" stroke="#ada68d" stroke-width="4"/>'
		"toll_receipt", "orra_charter":
			return '<path d="M32 19H99L94 104H28Z" fill="#d8ceb1"/><path d="M43 40H83M42 52H82M41 64H71M40 76H80" stroke="#574939" stroke-width="3"/><circle cx="80" cy="94" r="11" fill="#824d3c"/><path d="M77 103L73 117L82 112L87 117L84 103Z" fill="#824d3c"/>'
		"grain_ledger": return '<path d="M29 24L87 15L101 100L42 113L26 103Z" fill="#824d3c"/><path d="M39 27L90 20L96 101L46 108Z" fill="#d8ceb1"/><path d="M30 25L40 112M35 61L95 52" stroke="#574939" stroke-width="8"/><rect x="61" y="52" width="13" height="12" fill="#e1b978"/>'
		"rookwatch_seal", "ada_badge": return '<circle cx="64" cy="66" r="38" fill="%s"/><circle cx="64" cy="66" r="29" fill="#824d3c"/><path d="M43 83H85L81 50H87V37H76V46H69V36H59V46H52V37H41V50H47Z" fill="%s"/>' % [metal, warm]
		"hobb_ring": return '<circle cx="64" cy="70" r="32" fill="none" stroke="#e1b978" stroke-width="12"/><path d="M48 34L64 24L80 34L75 49H53Z" fill="#a38a51"/><path d="M57 30L65 26L70 34L63 40Z" fill="#d8ceb1"/>'
		"smith_hammer": return '<path d="M47 104L61 34" stroke="#574939" stroke-width="13"/><path d="M32 20L94 30L89 58L28 47Z" fill="#7b8881"/><path d="M32 20L41 23L37 48L28 47Z" fill="#a8b2aa"/>'
		"ferry_blankets": return '<path d="M26 31H98V54H26Z" fill="#ada68d"/><path d="M23 55H102V77H23Z" fill="#824d3c"/><path d="M27 79H99V103H27Z" fill="#d8ceb1"/><path d="M53 28V106M78 28V106" stroke="#574939" stroke-width="5"/>'
		"votive_candle": return '<path d="M49 53H80V106H49Z" fill="#d8ceb1"/><path d="M64 14Q93 43 65 52Q42 45 64 14Z" fill="#e1b978"/><path d="M64 33Q74 47 64 48Q56 45 64 33Z" fill="#d8ceb1"/><path d="M41 108H87" stroke="#7b8881" stroke-width="6"/>'
	return '<circle cx="64" cy="64" r="30" fill="%s"/>' % ink
