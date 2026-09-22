class_name SettingsPanel
extends VBoxContainer

var ui: Node
var content: VBoxContainer
var draft: Dictionary = {}
var capturing: StringName = &""
var capture_label: Label
var controls: Dictionary = {}

func configure(owner_ui: Node) -> void:
	ui = owner_ui
	content = UIStyle.scroll_content(self)

func refresh(preserve: bool = false) -> void:
	if not preserve or draft.is_empty():
		draft = SaveService.settings.duplicate(true)
	else:
		draft.bindings = SaveService.settings.bindings.duplicate(true)
	UIStyle.clear(content)
	controls.clear()
	content.add_child(UIStyle.label("Changes take effect when you choose Apply settings. Escape always remains Back.", true))
	_number("Mouse sensitivity", "mouse_sensitivity", 0.0001, 0.02, 0.0001)
	_toggle("Invert vertical look", "invert_y")
	_number("Vertical field of view", "fov", 60, 95, 1)
	_number("View bob (0 disables)", "view_bob", 0, 0.08, 0.01)
	_toggle("Camera shake", "camera_shake")
	_options("Text size", "text_scale", [1.0, 1.25, 1.5], ["100%", "125%", "150%"])
	_options("Rendering", "render_mode", ["retro", "native"], ["Retro (540p)", "Native"])
	_options("Shadows", "shadows", ["low", "high", "off"], ["Low", "High", "Off"])
	_toggle("Fullscreen", "fullscreen")
	_toggle("Vertical sync", "vsync")
	for bus: String in ["master", "ambience", "effects", "ui", "music"]:
		_number(bus.capitalize() + " volume", bus + "_volume", 0, 1, 0.05)
	content.add_child(UIStyle.button("Apply settings", _apply, "settings/apply"))
	content.add_child(UIStyle.label("Controls", true))
	capture_label = UIStyle.label("Choose an action, then press a key or mouse button. Escape cancels recording.", true)
	content.add_child(capture_label)
	for action: String in SettingsValidation.default_bindings():
		var chosen := StringName(action)
		var button := UIStyle.button(action.replace("_", " ").capitalize() + "   [" + InputBindings.label(chosen) + "]", func() -> void:
			capturing = chosen
			capture_label.text = "Press a key or mouse button for " + action.replace("_", " ") + ". Escape cancels."
		, "binding/" + action)
		content.add_child(button)

func _input(event: InputEvent) -> void:
	if capturing.is_empty() or not is_visible_in_tree():
		return
	var binding: Dictionary = {}
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			capturing = &""
			capture_label.text = "Binding unchanged."
			get_viewport().set_input_as_handled()
			return
		binding = {"type": "key", "code": int(event.physical_keycode)}
	elif event is InputEventMouseButton and event.pressed:
		binding = {"type": "mouse", "code": int(event.button_index)}
	else:
		return
	get_viewport().set_input_as_handled()
	var action := capturing
	capturing = &""
	var result := SaveService.rebind(action, binding)
	if result.code == &"binding_conflict":
		ui.confirm("Swap controls", "This input is assigned to " + String(result.payload.conflict).replace("_", " ") + ". Swap its binding with " + String(action).replace("_", " ") + "?", func() -> void:
			ui.report(SaveService.rebind(action, binding, true))
			refresh(true)
		)
	else:
		ui.report(result)
		refresh(true)

func _apply() -> void:
	var result := SaveService.save_settings(draft)
	ui.report(result, "Settings saved.")
	if result.ok:
		refresh()

func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var caption := UIStyle.label(title)
	caption.size_flags_stretch_ratio = 1.4
	row.add_child(caption)
	content.add_child(row)
	return row

func _number(title: String, key: String, low: float, high: float, step: float) -> void:
	var row := _row(title)
	var field := SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.step = step
	field.value = float(draft[key])
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(180, 44)
	field.value_changed.connect(func(value: float) -> void: draft[key] = value)
	field.set_meta("ui_id", "setting/" + key)
	row.add_child(field)
	controls[key] = field

func _toggle(title: String, key: String) -> void:
	var field := CheckButton.new()
	field.text = title
	field.button_pressed = bool(draft[key])
	field.custom_minimum_size.y = 44
	field.toggled.connect(func(value: bool) -> void: draft[key] = value)
	field.set_meta("ui_id", "setting/" + key)
	content.add_child(field)
	controls[key] = field

func _options(title: String, key: String, values: Array, labels: Array) -> void:
	var row := _row(title)
	var field := OptionButton.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size.y = 44
	for index: int in values.size():
		field.add_item(labels[index])
		if values[index] == draft[key]:
			field.select(index)
	field.item_selected.connect(func(index: int) -> void: draft[key] = values[index])
	field.set_meta("ui_id", "setting/" + key)
	row.add_child(field)
	controls[key] = field
