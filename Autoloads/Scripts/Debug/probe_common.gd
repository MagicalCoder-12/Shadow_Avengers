extends RefCounted
## Shared helpers for on-device performance probes.
## Reports are written to user://profiler_reports/ and a compact one-line
## summary is printed (visible via `adb logcat -s Godot`) so results can be
## read straight off the device.

const REPORT_DIR := "user://profiler_reports"

static func device_info() -> Dictionary:
	return {
		"model": OS.get_model_name(),
		"processor": OS.get_processor_name(),
		"godot": str(Engine.get_version_info().get("string", "?")),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")),
		"debug_build": OS.is_debug_build(),
		"screen": str(DisplayServer.window_get_size()),
	}

static func write_report(label: String, report: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var path := "%s/%s_%s.json" % [REPORT_DIR, stamp, label]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
		print("[PROFILER] ", label, " DONE: ", _summary(label, report))
		print("[PROFILER] report: ", ProjectSettings.globalize_path(path))
	else:
		print("[PROFILER] ", label, " FAILED to write report file")
	return path

## Compact single line for logcat — extend per probe by pre-setting
## report["summary"] before calling write_report.
static func _summary(label: String, report: Dictionary) -> String:
	if report.has("summary"):
		return str(report["summary"])
	var checks: Array = report.get("checks", [])
	if not checks.is_empty():
		var passed := 0
		for c in checks:
			if bool(c.get("ok", false)):
				passed += 1
		return "%d/%d checks passed" % [passed, checks.size()]
	return "%d bytes of metrics" % str(report).length()

static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

static func scene_manager() -> Node:
	var t := tree()
	return t.root.get_node_or_null("SceneManager")

## Navigate via the game's own scene loader and wait for arrival.
static func navigate_to(scene_path: String, timeout_s: float = 25.0) -> bool:
	var sm := scene_manager()
	if sm == null:
		print("[PROFILER] SceneManager missing — cannot navigate")
		return false
	var t := tree()
	if t.current_scene != null and str(t.current_scene.scene_file_path) == scene_path:
		return true
	sm.change_scene(scene_path)
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await t.process_frame
		var cs := t.current_scene
		if cs != null and str(cs.scene_file_path) == scene_path:
			# settle after load
			for _i in 60:
				await t.process_frame
			return true
	print("[PROFILER] navigation timeout waiting for ", scene_path)
	return false

static func count_nodes(root: Node) -> int:
	var stack: Array[Node] = [root]
	var total := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		total += 1
		for c in n.get_children():
			stack.append(c)
	return total

static func sample_loop(seconds: float, on_frame: Callable) -> void:
	var t := tree()
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		on_frame.call()
		await t.process_frame
