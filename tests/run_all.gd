extends SceneTree

var failures: int = 0
var checks: int = 0
var test_save_directory: String = ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL " + description)

func run() -> void:
	var selected: String = ""
	var worker: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--suite="):
			selected = argument.trim_prefix("--suite=")
		elif argument == "--worker":
			worker = true
	if worker:
		await run_suite(selected)
		return
	var suites := PackedStringArray()
	if not selected.is_empty():
		suites.append(selected if selected.begins_with("res://") or selected.is_absolute_path() else "res://tests/" + selected)
	else:
		for folder: String in ["unit", "integration"]:
			if not DirAccess.dir_exists_absolute("res://tests/" + folder):
				continue
			for file: String in DirAccess.get_files_at("res://tests/" + folder):
				if file.ends_with(".gd"):
					suites.append("res://tests/%s/%s" % [folder, file])
	suites.sort()
	if suites.is_empty():
		printerr("FAIL No test suites found.")
		quit(1)
		return
	var directory: String = OS.get_cache_dir().path_join("mireward-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		printerr("FAIL Cannot create isolated test directory.")
		quit(1)
		return
	var previous_directory: String = OS.get_environment("MIREWARD_TEST_SAVE_DIR")
	for suite_path: String in suites:
		var suite_directory: String = directory.path_join(str(suites.find(suite_path)))
		DirAccess.make_dir_recursive_absolute(suite_directory)
		OS.set_environment("MIREWARD_TEST_SAVE_DIR", suite_directory)
		var output: Array = []
		print("RUN " + suite_path)
		var status: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", suite_directory.path_join("engine.log"), "--script", "res://tests/run_all.gd", "--", "--worker", "--suite=" + suite_path], output, true)
		var transcript: String = "\n".join(output)
		var result_found: bool = false
		var suite_failed: bool = status != 0 or transcript.contains("SCRIPT ERROR:") or transcript.contains("ERROR:")
		for line: String in transcript.split("\n"):
			if line.begins_with("MIREWARD_TEST_RESULT "):
				var result: Variant = JSON.parse_string(line.trim_prefix("MIREWARD_TEST_RESULT "))
				if result is Dictionary and result.get("checks") is float and result.get("failures") is float:
					result_found = true
					checks += int(result.checks)
					suite_failed = suite_failed or result.failures > 0 or result.checks < 1
		if not result_found or suite_failed:
			failures += 1
			printerr("FAIL suite " + suite_path + " (exit %d)\n" % status + transcript)
	if previous_directory.is_empty():
		OS.unset_environment("MIREWARD_TEST_SAVE_DIR")
	else:
		OS.set_environment("MIREWARD_TEST_SAVE_DIR", previous_directory)
	remove_test_directory(directory)
	print("%s %d assertions, %d failed suites" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func run_suite(path: String) -> void:
	test_save_directory = OS.get_environment("MIREWARD_TEST_SAVE_DIR")
	if test_save_directory.is_empty():
		printerr("FAIL Worker requires an isolated save directory.")
		quit(1)
		return
	var timeout_seconds: float = 360.0 if path == "res://tests/integration/test_opening_walkthrough.gd" and OS.get_environment("MIREWARD_OPENING_WALKTHROUGH") == "1" else 120.0
	create_timer(timeout_seconds).timeout.connect(func() -> void:
		printerr("FAIL Test suite timed out: " + path)
		quit(1)
	)
	var script: Script = load(path)
	if script == null or not script.can_instantiate():
		printerr("FAIL Test suite cannot be loaded: " + path)
		quit(1)
		return
	var suite: Variant = script.new()
	if not suite is RefCounted or not suite.has_method("run"):
		printerr("FAIL Test suite must extend RefCounted and implement run(t): " + path)
		quit(1)
		return
	await suite.run(self)
	print("MIREWARD_TEST_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures == 0 and checks > 0 else 1)

func remove_test_directory(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for folder: String in DirAccess.get_directories_at(path):
		remove_test_directory(path.path_join(folder))
	DirAccess.remove_absolute(path)
