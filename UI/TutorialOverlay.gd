extends Control
class_name TutorialOverlay

## Campaign tutorial overlay. UI is defined in TutorialOverlay.tscn; this
## script fills it with step data and forwards button presses to
## TutorialManager via the continue_requested / skip_requested signals.
##
## Steps that carry a "target_path" use Clash-of-Clans-style highlighting:
## the screen is dimmed EXCEPT for a padded hole around the target control,
## with a pulsing gold border and a bobbing arrow. Touches inside the hole
## fall through to the real button (overlay root and rig use IGNORE filters);
## touches outside the hole are blocked by the dim rects. Steps without a
## target fall back to the plain full-screen Dimmer.

signal continue_requested
signal skip_requested
signal dismissed

const PROGRESS_FORMAT := "Step %d of %d"
const TARGET_PAD := 26.0
const ARROW_LENGTH := 150.0
const BORDER_PULSE_PERIOD := 0.9
const ARROW_BOB_PERIOD := 0.8
const ARROW_BOB_AMP := 14.0

@onready var _dimmer: ColorRect = $Dimmer
@onready var _portrait: TextureRect = $Card/HBoxContainer/Commander
@onready var _speaker: Label = $Card/HBoxContainer/Commander/Speaker
@onready var _dialogue: Label = $Card/HBoxContainer/VBoxContainer/Dialogue
@onready var _status: Label = $Card/HBoxContainer/VBoxContainer/Status
@onready var _progress: Label = $Card/ProgressLabel
@onready var _skip_button: Button = $Card/HBoxContainer/VBoxContainer/ButtonsHBox/Skip
@onready var _continue_button: Button = $Card/HBoxContainer/VBoxContainer/ButtonsHBox/Continue

var _dim_rig: Control
var _dim_rects: Array[ColorRect] = []
var _border: ReferenceRect
var _arrow: Polygon2D
var _callout: Label
var _callout_text := ""
var _target_node: Control
var _candidates: Array[Dictionary] = []
var _has_spotlight := false
var _arrow_points_down := true
var _arrow_base_y := 0.0
var _last_hole := Rect2()
var _time := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_spotlight_rig()

func _build_spotlight_rig() -> void:
	_dim_rig = Control.new()
	_dim_rig.name = "SpotlightRig"
	_dim_rig.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_rig.visible = false
	add_child(_dim_rig)
	# Above the Dimmer, below the Card.
	move_child(_dim_rig, 1)

	var dim_color := Color(0.12835406, 0.15170373, 0.29337206, 0.6)
	for rect_name in ["DimTop", "DimBottom", "DimLeft", "DimRight"]:
		var rect := ColorRect.new()
		rect.name = rect_name
		rect.color = dim_color
		rect.mouse_filter = Control.MOUSE_FILTER_STOP
		_dim_rig.add_child(rect)
		_dim_rects.append(rect)

	_border = ReferenceRect.new()
	_border.name = "TargetBorder"
	_border.border_color = Color(1.0, 0.78, 0.15)
	_border.border_width = 5.0
	_border.editor_only = false
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_rig.add_child(_border)

	_arrow = Polygon2D.new()
	_arrow.name = "Arrow"
	_arrow.polygon = PackedVector2Array([
		Vector2(-34, -34), Vector2(34, -34), Vector2(0, 34),
	])
	_arrow.color = Color(1.0, 0.78, 0.15)
	_dim_rig.add_child(_arrow)

	# Floating instruction text next to the arrow (CoC-style callout).
	_callout = Label.new()
	_callout.name = "Callout"
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout.add_theme_font_size_override("font_size", 34)
	_callout.add_theme_color_override("font_color", Color(1.0, 0.98, 0.92))
	_callout.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_callout.add_theme_constant_override("outline_size", 10)
	_dim_rig.add_child(_callout)

## Populate the overlay with one tutorial step. `portrait` may be null to
## keep the default artwork from the scene.
func present_step(step: Dictionary, portrait: Texture2D) -> void:
	if not is_node_ready():
		await ready
	_speaker.text = str(step.get("speaker", "COMMANDER ADRIAN"))
	_dialogue.text = str(step.get("text", ""))
	_status.text = str(step.get("status", ""))
	if portrait != null:
		_portrait.texture = portrait
	if step.has("step_index") and step.has("total_steps"):
		_progress.text = PROGRESS_FORMAT % [int(step["step_index"]), int(step["total_steps"])]
		_progress.show()
	else:
		_progress.hide()
	_continue_button.visible = str(step.get("completion", "continue")) == "continue"
	_skip_button.visible = bool(step.get("allow_skip", true))
	_setup_spotlight(step)

## Resolve target_path, show the spotlight rig, hide the full Dimmer. Falls
## back to the plain dimmer when there is no resolvable target.
func _setup_spotlight(step: Dictionary) -> void:
	_target_node = null
	_has_spotlight = false
	_dim_rig.visible = false
	_dimmer.visible = true
	_time = 0.0
	# Spotlight steps put the instruction next to the arrow; other steps keep
	# it in the card only.
	var status_txt := str(step.get("status", ""))
	_callout_text = ""
	# Build the fallback chain: "target_paths" entries take priority over a
	# single "target_path". Each entry: {"path": String, "status": String}.
	_candidates.clear()
	for tp in step.get("target_paths", []):
		if tp is Dictionary and tp.has("path"):
			_candidates.append({"path": str(tp["path"]), "status": str(tp.get("status", ""))})

	var target_path := str(step.get("target_path", ""))
	if _candidates.is_empty() and not target_path.is_empty():
		_candidates.append({"path": target_path, "status": ""})
	if _candidates.is_empty() or get_tree().current_scene == null:
		return
	# Await a frame so freshly built menus finish their layout pass first.
	await get_tree().process_frame
	# Never leave the full-screen Dimmer up for a spotlight step: enable the
	# rig and let _layout_spotlight resolve the first visible candidate every
	# frame (all bands stay hidden while nothing is resolvable, so touches are
	# never blocked).
	_has_spotlight = true
	_dim_rig.visible = true
	_dimmer.visible = false
	if status_txt.is_empty() and _candidates.size() > 0:
		for c in _candidates:
			var st := str(c.get("status", ""))
			if not st.is_empty():
				_callout_text = st
				break
	else:
		_callout_text = status_txt if not status_txt.is_empty() else str(step.get("text", ""))
	_resolve_candidate()
	_layout_spotlight()
	DebugFlags.debug_print("[TUTORIAL] spotlight candidates=%s hole=%s" % [str(_candidates), str(_last_hole)])

## Resolves the first VISIBLE candidate target and switches to it when it
## changes (e.g. BUY hides after purchase, so the spotlight moves to the
## coin-upgrade button). Returns false when nothing is highlightable.
func _resolve_candidate() -> bool:
	var cs: Node = get_tree().current_scene
	for c in _candidates:
		var t := (cs.get_node_or_null(str(c["path"])) as Control) if cs else null
		if t != null and t.is_visible_in_tree():
			if t != _target_node:
				_target_node = t
				_last_hole = Rect2()
			var st := str(c["status"])
			if not st.is_empty():
				_callout_text = st
			return true
	return false

func _layout_spotlight() -> void:
	# Re-resolve every frame so one step can cover state changes.
	if not _resolve_candidate():
		# Nothing to highlight right now: keep the whole rig hidden so touches
		# are NOT blocked (never strand the player behind a blind overlay).
		for r in _dim_rects:
			r.visible = false
		_border.visible = false
		_arrow.visible = false
		_callout.visible = false
		_target_node = null
		_last_hole = Rect2()
		return
	_border.visible = true
	_arrow.visible = true
	if _target_node == null or not is_instance_valid(_target_node):
		return
	# Work in SCREEN space: the target may live in another CanvasLayer with
	# its own transform (e.g. the map's UI layer), so canvas-space rects would
	# be wrong. get_screen_transform() bakes every layer transform in.
	var tx := _target_node.get_screen_transform()
	var p1: Vector2 = tx * Vector2.ZERO
	var p2: Vector2 = tx * _target_node.size
	var s_rect := Rect2(Vector2(minf(p1.x, p2.x), minf(p1.y, p2.y)),
						(p1 - p2).abs()).grow(TARGET_PAD)
	# Screen -> overlay-local space.
	var inv: Transform2D = _dim_rig.get_screen_transform().affine_inverse()
	var q1: Vector2 = inv * s_rect.position
	var q2: Vector2 = inv * s_rect.end
	var hole := Rect2(Vector2(minf(q1.x, q2.x), minf(q1.y, q2.y)), (q1 - q2).abs())

	var vp := _dim_rig.size

	var rects := [
		[Vector2(0, 0), Vector2(vp.x, maxf(hole.position.y, 0.0))],
		[Vector2(0, hole.end.y), Vector2(vp.x, maxf(vp.y - hole.end.y, 0.0))],
		[Vector2(0, hole.position.y), Vector2(maxf(hole.position.x, 0.0), hole.size.y)],
		[Vector2(hole.end.x, hole.position.y), Vector2(maxf(vp.x - hole.end.x, 0.0), hole.size.y)],
	]
	for i in rects.size():
		var r: ColorRect = _dim_rects[i]
		r.position = rects[i][0]
		r.size = rects[i][1]
		r.visible = rects[i][1].x > 0.5 and rects[i][1].y > 0.5

	_border.position = hole.position
	_border.size = hole.size
	_last_hole = hole

	var center := hole.get_center()
	# Button in the lower part of the screen -> arrow floats ABOVE it pointing
	# down into the hole; otherwise arrow floats BELOW pointing up.
	_arrow_points_down = center.y > vp.y * 0.62
	if _arrow_points_down:
		_arrow_base_y = hole.position.y - 34.0 - 4.0
		_arrow.scale = Vector2(1, 1)
	else:
		_arrow_base_y = hole.end.y + 34.0 + 4.0
		_arrow.scale = Vector2(1, -1)
	_arrow.position = Vector2(center.x, _arrow_base_y)

	# Callout text stacked against the arrow, clamped to the viewport.
	if _callout_text.is_empty():
		_callout.visible = false
	else:
		_callout.visible = true
		if _callout.text != _callout_text:
			_callout.text = _callout_text
			_callout.reset_size()
		var cp := Vector2(
			clampf(center.x - _callout.size.x * 0.5, 8.0, maxf(vp.x - _callout.size.x - 8.0, 8.0)),
			(_arrow_base_y - _callout.size.y - 10.0) if _arrow_points_down else (_arrow_base_y + 34.0 + 10.0))
		cp.y = clampf(cp.y, 4.0, maxf(vp.y - _callout.size.y - 4.0, 4.0))
		_callout.position = cp

func _process(delta: float) -> void:
	if _has_spotlight:
		_time += delta
		# Re-layout every frame so scrolling menus keep the hole on target.
		_layout_spotlight()
		var pulse := 0.5 + 0.5 * sin(TAU * _time / BORDER_PULSE_PERIOD)
		_border.border_color.a = 0.55 + 0.45 * pulse
		_border.border_width = 5.0 + 2.0 * pulse
		# Bob toward the button.
		_arrow.position.y = _arrow_base_y + ARROW_BOB_AMP * sin(TAU * _time / ARROW_BOB_PERIOD) * (1.0 if _arrow_points_down else -1.0)

## Fade the whole overlay out, then report back so TutorialManager can free it.
func fade_out_and_dismiss() -> void:
	if not is_node_ready():
		await ready
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished
	hide()
	dismissed.emit()

func _on_continue_pressed() -> void:
	continue_requested.emit()

func _on_skip_pressed() -> void:
	skip_requested.emit()
