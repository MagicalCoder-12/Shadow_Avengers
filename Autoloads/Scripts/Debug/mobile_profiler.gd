extends CanvasLayer
## On-device profiler overlay (debug/profiling builds only).
##
## Active only when the exported build includes the custom "profiler" feature
## (set in export_presets.cfg custom_features). In normal builds this node
## frees itself in _ready, leaving zero footprint.
##
## Provides: live FPS/process/physics/draw/VRAM/node stats, one-tap baseline
## and gameplay-flow probes (reports in user://profiler_reports/ + logcat
## under the Godot tag), an FPS-cap cycler, and a clean exit button.

const PROBE_DIR := "res://Autoloads/Scripts/Debug/"
const REPORT_DIR := "user://profiler_reports"
# Loaded at runtime (not preload) so a release export can exclude the probe
# scripts entirely without breaking this autoload's parse.
var ProbeCommon: GDScript = null
var ProbeBaseline: GDScript = null
var ProbeFlow: GDScript = null

const FONT_SIZE_STATS := 26
const FONT_SIZE_BUTTON := 30
const STATS_INTERVAL := 0.25

var _panel: PanelContainer
var _btn_list: Array[Button] = []
var _stats: Label
var _status: Label
var _toggle: Button
var _busy := false
var _stats_accum := 0.0
var _fps_cap := 0

func _ready() -> void:
	# Zero footprint unless this is a debug/profiling build. DebugFlags.profiling
	# is false in any release export that did not opt into the "profiler" or
	# "debug_tools" custom feature, so the overlay cannot reach players.
	# DebugFlags.profiling already requires a debug build, so nothing here can
	# bring the overlay into a release binary.
	if not DebugFlags.profiling:
		queue_free()
		return
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	var probes_ok := _load_probe_scripts()
	_build_ui(probes_ok)
	print("[PROFILER] overlay active (debug/profiling build)")

## Probe scripts are excluded from release exports; when that happens the
## overlay still works, it just hides the probe buttons.
func _load_probe_scripts() -> bool:
	ProbeCommon = load(PROBE_DIR + "probe_common.gd") as GDScript
	ProbeBaseline = load(PROBE_DIR + "probe_baseline.gd") as GDScript
	ProbeFlow = load(PROBE_DIR + "probe_flow.gd") as GDScript
	return ProbeCommon != null and ProbeBaseline != null and ProbeFlow != null

## Counts every node in the tree (local copy so the overlay does not depend on
## the probe scripts, which release exports exclude).
func _count_nodes(root: Node) -> int:
	if root == null:
		return 0
	var total := 1
	for child in root.get_children():
		total += _count_nodes(child)
	return total

func _build_ui(probes_ok: bool = true) -> void:
	var root := Control.new()
	root.name = "ProfilerRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 4096
	add_child(root)

	_toggle = Button.new()
	_toggle.text = "PROF"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.add_theme_font_size_override("font_size", 72)
	_toggle.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_toggle.position = Vector2(20, 170)
	_toggle.size = Vector2(380, 170)
	_toggle.pressed.connect(_on_toggle)
	root.add_child(_toggle)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(16, 148)
	_panel.custom_minimum_size = Vector2(1100, 0)
	_panel.visible = false
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 44)
	_stats.text = "..."
	box.add_child(_stats)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 44)
	_status.text = "ready"
	box.add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	if probes_ok:
		row.add_child(_make_button("BASELINE", _run_baseline))
		row.add_child(_make_button("FLOW", _run_flow))

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 16)
	box.add_child(row2)
	row2.add_child(_make_button("FPS CAP", _cycle_fps_cap))
	row2.add_child(_make_button("UI DUMP", _dump_ui))
	row2.add_child(_make_button("TUT RESET", _reset_tutorial))
	row2.add_child(_make_button("EXIT", _on_exit))

func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 48)
	b.custom_minimum_size = Vector2(340, 120)
	b.pressed.connect(func() -> void: print("[PROFILER] pressed ", text))
	b.pressed.connect(handler)
	_btn_list.append(b)
	return b

func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	print("[PROFILER] panel ", "open" if _panel.visible else "closed")
	if _panel.visible:
		# One tap = full ground-truth capture: wait for layout, log every
		# button rect post-layout, then dump the whole current scene's UI.
		await get_tree().process_frame
		await get_tree().process_frame
		for b: Button in [_toggle] + _btn_list:
			var r := b.get_global_rect()
			print("[PROFILER] btn %s at (%.0f,%.0f)-(%.0f,%.0f)" % [b.text, r.position.x, r.position.y, r.end.x, r.end.y])
		_dump_ui()

## Walk the current scene and print every visible Control's laid-out size
## (in design-space units) so UI scaling problems can be measured on-device.
func _unhandled_key_input(event: InputEvent) -> void:
	# Hardware-key shortcuts so probes can be triggered over ADB without
	# touch-coordinate guesswork: VOL UP = UI dump, VOL DOWN = toggle panel.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_VOLUMEUP:
				_dump_ui()
				get_viewport().set_input_as_handled()
			KEY_VOLUMEDOWN:
				_on_toggle()
				get_viewport().set_input_as_handled()

func _dump_ui() -> void:
	var cs: Node = get_tree().current_scene
	if cs == null:
		print("[UIDUMP] no scene")
		return
	print("[UIDUMP] scene=%s viewport=%s" % [cs.scene_file_path, str(get_tree().root.get_visible_rect().size)])
	_dump_recursive(cs, 0)
	print("[UIDUMP] end")

func _dump_recursive(node: Node, depth: int) -> void:
	if node is Control:
		var c := node as Control
		if c.is_visible_in_tree():
			var fs := -1
			if c is Label or c is Button or c is LineEdit:
				var override: int = c.get_theme_font_size("font_size")
				fs = override
			print("[UIDUMP] %s%s|%s|pos=(%.0f,%.0f)|size=(%.0f,%.0f)|min=(%.0f,%.0f)|font=%d" % [
				"  ".repeat(mini(depth, 8)), c.name, c.get_class(),
				c.global_position.x, c.global_position.y,
				c.size.x, c.size.y,
				c.get_combined_minimum_size().x, c.get_combined_minimum_size().y, fs])
	for child in node.get_children():
		_dump_recursive(child, depth + 1)

func _reset_tutorial() -> void:
	print("[PROFILER] tutorial reset requested")
	var sm := get_node_or_null("/root/SaveManager")
	var tm := get_node_or_null("/root/TutorialManager")
	if sm == null or tm == null:
		_status.text = "tut reset FAILED"
		return
	# Re-arm the new-player campaign so map/shop steps replay, then jump to
	# the map where the shop spotlight step lives.
	if sm.has_method("set_tutorial_campaign_stage"):
		sm.call("set_tutorial_campaign_stage", "shop_entry")
	var ts: Dictionary = sm.get("tutorial_state")
	ts["eligible_for_automatic_tutorials"] = true
	sm.set("tutorial_state", ts)
	if sm.has_method("save_progress"):
		sm.call("save_progress", true)
	_status.text = "tut: shop_entry armed"
	print("[PROFILER] tutorial stage=shop_entry armed, going to map")
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("change_scene") and gm.has_method("get_map_scene_path"):
		_panel.visible = false
		gm.call("change_scene", gm.call("get_map_scene_path"))

func _on_exit() -> void:
	if _busy:
		return
	print("[PROFILER] exit requested from overlay")
	get_tree().quit()

func _cycle_fps_cap() -> void:
	_fps_cap = 60 if _fps_cap == 0 else (120 if _fps_cap == 60 else 0)
	Engine.max_fps = _fps_cap
	_status.text = "fps cap: %s" % ("uncapped" if _fps_cap == 0 else str(_fps_cap))

func _run_baseline() -> void:
	if ProbeBaseline == null:
		_status.text = "probes excluded from this build"
		return
	_start_probe(ProbeBaseline.new(), "baseline")

func _run_flow() -> void:
	if ProbeFlow == null:
		_status.text = "probes excluded from this build"
		return
	_start_probe(ProbeFlow.new(), "flow")

func _start_probe(probe: RefCounted, kind: String) -> void:
	if _busy:
		_status.text = "probe already running"
		return
	_busy = true
	_status.text = "%s probe running..." % kind
	var label := "%s_%d" % [kind, Time.get_ticks_msec()]
	probe.set_meta("_running", true)
	# Run on the next frame so the button press settles first.
	await get_tree().process_frame
	probe.run(label)
	_watch_probe(probe, kind)

func _watch_probe(probe: RefCounted, kind: String) -> void:
	while is_instance_valid(probe) and bool(probe.get_meta("_running", false)):
		await get_tree().create_timer(0.5).timeout
	_status.text = "%s probe: done — summary below" % kind
	_show_latest_summary(kind)

func _show_latest_summary(kind: String) -> void:
	var dir: DirAccess = DirAccess.open(REPORT_DIR)
	if dir == null:
		_status.text = "no report dir"
		_busy = false
		return
	var best_name := ""
	var best_ms := 0
	for f in dir.get_files():
		if not f.begins_with(kind) or not f.ends_with(".json"):
			continue
		var ms := f.get_slice("_", 1).to_int()
		if ms > best_ms:
			best_ms = ms
			best_name = f
	if best_name.is_empty():
		_status.text = "no report found"
		_busy = false
		return
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(REPORT_DIR + "/" + best_name))
	if parsed is Dictionary:
		var lines: Array[String] = []
		var checks: Array = parsed.get("checks", [])
		if not checks.is_empty():
			for c in checks:
				lines.append("%s: %s" % [c.get("name", "?"), "OK" if c.get("ok") else "FAIL"])
		for seg: Dictionary in parsed.get("segments", []):
			if seg.has("error"):
				lines.append("%s: %s" % [seg.get("name", "?"), seg["error"]])
			else:
				lines.append("%s: fps=%.1f min=%.0f proc=%.1fms phys=%.2fms draws=%.0f nodes=%d vram=%.0fMB" % [
					seg.get("name", "?"), seg.get("fps_avg", 0.0), seg.get("fps_min", 0.0),
					seg.get("process_ms_avg", 0.0), seg.get("physics_ms_avg", 0.0),
					seg.get("draw_calls_avg", 0.0), seg.get("node_count", 0),
					seg.get("video_mem_mb", 0.0)])
		if parsed.has("combat"):
			var c: Dictionary = parsed["combat"]
			lines.append("combat: fps=%.1f min=%.0f nodes=%d bullets=%d" % [
				c.get("fps_avg", 0.0), c.get("fps_min", 0.0),
				c.get("nodes_max", 0), c.get("enemy_bullets_max", 0)])
		_status.text = "\n".join(lines)
	_busy = false

func _process(delta: float) -> void:
	_stats_accum += delta
	if _stats_accum < STATS_INTERVAL:
		return
	_stats_accum = 0.0
	if _panel != null and _panel.visible:
		var t: SceneTree = get_tree()
		var cs: Node = t.current_scene
		var scene_name: String = cs.scene_file_path.get_file() if cs != null else "-"
		_stats.text = "\n".join([
			"scene: %s" % scene_name,
			"fps: %d  (cap %s)" % [Engine.get_frames_per_second(), "off" if _fps_cap == 0 else str(_fps_cap)],
			"proc: %.2f ms  phys: %.2f ms" % [
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0],
			"draws: %d  objs: %d" % [
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)],
			"vram: %.0f MB  mem: %.0f MB" % [
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0],
			"nodes: %d" % _count_nodes(t.root),
		])
