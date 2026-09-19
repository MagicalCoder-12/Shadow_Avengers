extends RefCounted
## On-device baseline probe: samples FPS / process / physics / draw calls /
## VRAM / node counts on start_menu, map, and level_0 combat.
## Driven by MobileProfiler; independent of the Fennara runtime addon.

const ProbeCommon := preload("res://Autoloads/Scripts/Debug/probe_common.gd")
const LEVEL_SCENE := "res://Levels/level_0.tscn"
const COMBAT_DURATION := 12.0
## Set true to tap through the level-0 onboarding tutorial before sampling.
const SKIP_TUTORIAL := true

var report: Dictionary = {}

func run(label: String) -> void:
	report = {"probe": "baseline", "device": ProbeCommon.device_info(), "segments": []}
	var t := ProbeCommon.tree()

	# Segment 1: current scene (start menu at boot)
	await _sample_segment("start_menu", 6.0)

	# Segment 2: map
	if not await ProbeCommon.navigate_to("res://Map/map.tscn"):
		report["segments"].append({"name": "map", "error": "navigation failed"})
	else:
		await _sample_segment("map", 6.0)

	# Segment 3: level_0 combat
	if not await ProbeCommon.navigate_to(LEVEL_SCENE):
		report["segments"].append({"name": "level_0", "error": "navigation failed"})
	else:
		if SKIP_TUTORIAL:
			await _dismiss_tutorial()
		await _sample_segment("level_0", COMBAT_DURATION)

	var f := FileAccess.open("user://last_probe_label.txt", FileAccess.WRITE)
	if f:
		f.store_string(label)
		f.close()
	ProbeCommon.write_report(label, report)
	Engine.max_fps = 0
	set_meta("_running", false)

func get_tree() -> SceneTree:
	return ProbeCommon.tree()

func _sample_segment(seg_name: String, seconds: float) -> void:
	var t := ProbeCommon.tree()
	var fps: Array[float] = []
	var proc: Array[float] = []
	var phys: Array[float] = []
	var draws: Array[float] = []
	var nodes: Array[int] = []
	var sample := func() -> void:
		fps.append(Performance.get_monitor(Performance.TIME_FPS))
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draws.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		nodes.append(ProbeCommon.count_nodes(t.root))
	await ProbeCommon.sample_loop(seconds, sample)

	var root := t.current_scene
	var seg := {
		"name": seg_name,
		"scene": str(root.scene_file_path) if root else "",
		"fps_avg": _avg(fps), "fps_min": _minv(fps), "fps_max": _maxv(fps),
		"process_ms_avg": _avg(proc), "process_ms_max": _maxv(proc),
		"physics_ms_avg": _avg(phys), "physics_ms_max": _maxv(phys),
		"draw_calls_avg": _avg(draws), "draw_calls_max": _maxv(draws),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"node_count": nodes.max() if nodes.size() > 0 else 0,
	}
	report["segments"].append(seg)
	var s := "fps=%.1f min=%.0f proc=%.1fms phys=%.2fms draws=%.0f nodes=%d vram=%.0fMB"
	print("[PROFILER] segment ", seg_name, ": ", s % [
		seg["fps_avg"], seg["fps_min"], seg["process_ms_avg"],
		seg["physics_ms_avg"], seg["draw_calls_avg"], seg["node_count"], seg["video_mem_mb"]])

func _dismiss_tutorial() -> void:
	var t := ProbeCommon.tree()
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await t.process_frame
		var cs := t.current_scene
		var overlay: Node = cs.find_child("TutorialOverlay", true, false) if cs else null
		if overlay == null:
			return
		var btn: Node = overlay.find_child("Continue", true, false)
		if btn is BaseButton:
			(btn as BaseButton).pressed.emit()
		await t.create_timer(0.7).timeout
	print("[PROFILER] warning: tutorial did not fully dismiss in 10s")

func _avg(a: Array[float]) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for v in a: s += v
	return s / a.size()

func _minv(a: Array[float]) -> float:
	var m := 99999.0
	for v in a: m = minf(m, v)
	return m if not a.is_empty() else 0.0

func _maxv(a: Array[float]) -> float:
	var m := 0.0
	for v in a: m = maxf(m, v)
	return m
