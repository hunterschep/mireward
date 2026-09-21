extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var errors := ContentValidation.validate(root.get_node("ContentDB"), "--release" in OS.get_cmdline_user_args())
	for error: String in errors:
		printerr(error)
	if errors.is_empty():
		print("PASS content validation: 23 items, 5 enemy types, 12 quest IDs, 8 speakers, 9 landmarks, 26 spawns")
	quit(0 if errors.is_empty() else 1)
