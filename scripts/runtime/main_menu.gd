extends Control

func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	center.add_child(column)
	var title := Label.new()
	title.text = "M I R E W A R D"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color("d8ceb1"))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "A borrowed sword. A broken road. A promise worth keeping."
	column.add_child(subtitle)
	var status := Label.new()
	status.text = "Foundation checkpoint · campaign integration in progress"
	column.add_child(status)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(get_tree().quit)
	column.add_child(quit)
	quit.grab_focus()
