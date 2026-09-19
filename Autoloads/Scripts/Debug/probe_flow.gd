extends RefCounted
## On-device gameplay flow probe: drives level_0 and verifies the loop:
## player spawn, tutorial overlay present/dismiss, enemy spawn, sustained
## fire, and player survival. Reports to user:// + logcat.

const ProbeCommon := preload("res://Autoloads/Scripts/Debug/probe_common.gd")
const LEVEL_SCENE := "res://Levels/level_0.tscn"

var report: Dictionary = {}

func run(label: String) -> void:
	report = {"probe": "flow", "device": ProbeCommon.device_info(), "checks": []}
	var t := ProbeCommon.tree()

	if not await ProbeCommon.navigate_to(LEVEL_SCENE):
		_check("level_0_loaded", false, {})
		_finish(label)
		return
	_check("level_0_loaded", true, {})
	await t.create_timer(2.0).timeout

	var player: Node = t.get_first_node_in_group("Player")
	_check("player_spawned", player != null, {})

	# Tutorial overlay should appear for a fresh level-0 profile.
	var overlay_found := await _wait_until(func() -> bool:
		var cs := t.current_scene
		return cs != null and cs.find_child("TutorialOverlay", true, false) != null,
		8.0)
	_check("tutorial_overlay_present", overlay_found, {})

	await _dismiss_tutorial()
	var overlay_gone: Node = t.current_scene.find_child("TutorialOverlay", true, false) if t.current_scene else null
	_check("tutorial_dismissed", overlay_gone == null, {})

	# Enemies should spawn within 25s.
	var enemies_found := await _wait_until(func() -> bool:
		return t.get_nodes_in_group("Enemy").size() > 0,
		25.0)
	_check("enemies_spawned", enemies_found, {"count": t.get_nodes_in_group("Enemy").size()})

	# Hold fire for 8 seconds, sampling fps and node counts.
	var fps: Array[float] = []
	var nodes: Array[int] = []
	var bullets: Array[int] = []
	var sample := func() -> void:
		fps.append(Performance.get_monitor(Performance.TIME_FPS))
		nodes.append(ProbeCommon.count_nodes(t.root))
		bullets.append(t.get_nodes_in_group("EnemyBullet").size())
	Input.action_press("shoot")
	await ProbeCommon.sample_loop(8.0, sample)
	Input.action_release("shoot")

	var s := 0.0
	var fmin := 9999.0
	for v in fps:
		s += v
		fmin = minf(fmin, v)
	var combat := {
		"fps_avg": s / maxf(1.0, float(fps.size())),
		"fps_min": fmin,
		"nodes_max": nodes.max() if nodes.size() > 0 else 0,
		"enemy_bullets_max": bullets.max() if bullets.size() > 0 else 0,
	}
	report["combat"] = combat
	print("[PROFILER] combat: fps=%.1f min=%.0f nodes=%d bullets=%d" % [
		combat["fps_avg"], combat["fps_min"], combat["nodes_max"], combat["enemy_bullets_max"]])

	var player_after: Node = t.get_first_node_in_group("Player")
	_check("player_alive_after_combat", player_after != null and (player_after as Node2D).is_inside_tree(), {})

	_finish(label)

func _finish(label: String) -> void:
	var passed := 0
	for c in report["checks"]:
		if bool(c.get("ok", false)):
			passed += 1
	report["summary"] = "%d/%d checks passed" % [passed, report["checks"].size()]
	for c in report["checks"]:
		print("[PROFILER] check ", c.get("name"), ": ", "OK" if c.get("ok") else "FAIL")
	ProbeCommon.write_report(label, report)
	set_meta("_running", false)

func get_tree() -> SceneTree:
	return ProbeCommon.tree()

func _check(nm: String, ok: bool, detail: Dictionary) -> void:
	report["checks"].append({"name": nm, "ok": ok, "detail": detail})

func _wait_until(predicate: Callable, timeout_s: float) -> bool:
	var t := ProbeCommon.tree()
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await t.process_frame
	return false

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
