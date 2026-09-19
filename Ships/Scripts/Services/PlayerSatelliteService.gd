extends RefCounted
class_name PlayerSatelliteService

const DEFAULT_SHIP_VISUAL_SIZE := Vector2(160.0, 120.0)
const DEFAULT_SATELLITE_VISUAL_SIZE := Vector2(96.0, 96.0)
const SATELLITE_SIZE_RATIO: float = 0.8
const MIN_EDGE_GAP: float = 8.0
const EDGE_GAP_RATIO: float = 0.04

var _owner: Node2D
var _sprite: Sprite2D
var _game_manager: Node
var _debug_callback: Callable

var satellites: Array[Node2D] = []
var satellite_scenes: Dictionary = {}

const SATELLITE_IDS: Array[String] = ["Satellite1", "Satellite2", "Satellite3", "Satellite4", "Satellite5", "Satellite6"]

func configure(owner: Node2D, sprite: Sprite2D, game_manager: Node, debug_callback: Callable) -> void:
	_owner = owner
	_sprite = sprite
	_game_manager = game_manager
	_debug_callback = debug_callback

func initialize_satellites() -> void:
	load_satellite_scenes()
	add_satellites_from_selection()

func load_satellite_scenes() -> void:
	satellite_scenes.clear()
	for satellite_id in SATELLITE_IDS:
		var scene_path = "res://Satellites/%s.tscn" % satellite_id
		if ResourceLoader.exists(scene_path):
			satellite_scenes[satellite_id] = load(scene_path)
		else:
			push_warning("Satellite scene not found: " + scene_path)

func add_satellites_from_selection() -> void:
	if not _owner:
		return
	if not _owner.is_inside_tree():
		await _owner.tree_entered

	for i in range(2):
		var satellite_id := _get_selected_satellite_id(i)
		if satellite_id.is_empty() or not _is_satellite_unlocked(satellite_id):
			# Locked satellites must never render (e.g. before the shop
			# tutorial hands the player their first drone).
			continue
		var satellite_scene: PackedScene = satellite_scenes.get(satellite_id)
		if satellite_scene:
			add_satellite(satellite_scene, i)
		else:
			push_warning("Satellite scene not loaded for: " + satellite_id)

func add_satellite(satellite_scene: PackedScene, position_index: int) -> void:
	if not _owner:
		return
	if not satellite_scene or not satellite_scene.can_instantiate():
		push_error("Invalid satellite scene")
		return

	var satellite_id := _get_selected_satellite_id(position_index)
	var satellite = satellite_scene.instantiate() as Node2D
	if not satellite:
		push_error("Failed to instantiate satellite")
		return

	satellite.name = "Satellite%d" % position_index
	_owner.add_child(satellite)
	satellites.append(satellite)

	if satellite.has_method("set_satellite_id"):
		satellite.set_satellite_id(satellite_id)
	elif satellite.has_signal("satellite_id_set"):
		satellite.set("satellite_id", satellite_id)
	else:
		satellite.set_meta("satellite_id", satellite_id)

	refresh_satellite_layout()
	_debug("Added satellite %s at offset %s" % [satellite.name, str(satellite.position)])

func remove_all_satellites() -> void:
	for satellite in satellites:
		if satellite and is_instance_valid(satellite):
			if satellite.has_method("set_shooting_active"):
				satellite.set_shooting_active(false)
			if _owner and satellite.get_parent() == _owner:
				_owner.remove_child(satellite)
			satellite.queue_free()
	satellites.clear()
	_debug("Removed all satellites")

func update_satellites_from_selection() -> void:
	remove_all_satellites()
	add_satellites_from_selection()

func refresh_satellite_layout() -> void:
	if not _owner:
		return

	var ship_bounds := _get_ship_visual_bounds_local()
	var ship_visual_size := ship_bounds.size if ship_bounds.size != Vector2.ZERO else DEFAULT_SHIP_VISUAL_SIZE

	for index in range(satellites.size()):
		var satellite := satellites[index]
		if not satellite or not is_instance_valid(satellite):
			continue

		_fit_satellite_to_ship(satellite, ship_visual_size)
		satellite.position = _calculate_satellite_position_for_bounds(
			_get_satellite_visual_bounds_local(satellite),
			ship_bounds,
			index
		)

func on_satellite_stats_updated(satellite_id: String, damage_bonus: int) -> void:
	for satellite in satellites:
		if not satellite or not is_instance_valid(satellite):
			continue
		var instance_satellite_id: String = ""
		if satellite.has_method("get_satellite_id"):
			instance_satellite_id = str(satellite.call("get_satellite_id"))
		elif satellite.has_meta("satellite_id"):
			instance_satellite_id = str(satellite.get_meta("satellite_id"))
		if instance_satellite_id != satellite_id:
			continue
		if satellite.has_method("apply_damage_bonus"):
			satellite.apply_damage_bonus(damage_bonus)
	_debug("Updated damage bonus for satellites of type %s: +%d" % [satellite_id, damage_bonus])

func calculate_satellite_offset(position_index: int) -> Vector2:
	var ship_bounds := _get_ship_visual_bounds_local()
	var satellite_bounds := Rect2(-DEFAULT_SATELLITE_VISUAL_SIZE * 0.5, DEFAULT_SATELLITE_VISUAL_SIZE * SATELLITE_SIZE_RATIO)

	if position_index >= 0 and position_index < satellites.size():
		var satellite := satellites[position_index]
		if satellite and is_instance_valid(satellite):
			satellite_bounds = _get_satellite_visual_bounds_local(satellite)

	return _calculate_satellite_position_for_bounds(satellite_bounds, ship_bounds, position_index)

func _is_satellite_unlocked(satellite_id: String) -> bool:
	if satellite_id.is_empty():
		return false
	if _game_manager and _game_manager.player_manager and _game_manager.player_manager.has_method("is_satellite_unlocked"):
		return bool(_game_manager.player_manager.call("is_satellite_unlocked", satellite_id))
	if _game_manager and _game_manager.satellites is Array:
		for satellite in _game_manager.satellites:
			if satellite is Dictionary and str(satellite.get("id", "")) == satellite_id:
				return bool(satellite.get("unlocked", false))
	return false

func _get_selected_satellite_id(index: int) -> String:
	var satellite_id := "Satellite1"
	if _game_manager and _game_manager.player_manager:
		if _game_manager.player_manager.has_method("get_selected_satellite_id"):
			satellite_id = _game_manager.player_manager.get_selected_satellite_id(index)
		elif index < _game_manager.player_manager.selected_satellite_ids.size():
			satellite_id = _game_manager.player_manager.selected_satellite_ids[index]
	return satellite_id

func _debug(message: String) -> void:
	if _debug_callback.is_valid():
		_debug_callback.call(message)

func _fit_satellite_to_ship(satellite: Node2D, ship_visual_size: Vector2) -> void:
	if satellite.has_method("apply_ship_relative_size"):
		satellite.call("apply_ship_relative_size", ship_visual_size, SATELLITE_SIZE_RATIO)
		return

	var satellite_bounds := _get_satellite_visual_bounds_local(satellite)
	if ship_visual_size == Vector2.ZERO or satellite_bounds.size == Vector2.ZERO:
		return

	var target_size := ship_visual_size * SATELLITE_SIZE_RATIO
	var scale_factor_x := target_size.x / satellite_bounds.size.x if satellite_bounds.size.x > 0.0 else 1.0
	var scale_factor_y := target_size.y / satellite_bounds.size.y if satellite_bounds.size.y > 0.0 else 1.0
	var scale_factor := minf(scale_factor_x, scale_factor_y)
	if not is_finite(scale_factor) or scale_factor <= 0.0:
		return

	satellite.scale *= scale_factor

func _calculate_satellite_position_for_bounds(satellite_bounds: Rect2, ship_bounds: Rect2, position_index: int) -> Vector2:
	var safe_ship_bounds := ship_bounds
	if safe_ship_bounds.size == Vector2.ZERO:
		safe_ship_bounds = Rect2(-DEFAULT_SHIP_VISUAL_SIZE * 0.5, DEFAULT_SHIP_VISUAL_SIZE)

	var safe_satellite_bounds := satellite_bounds
	if safe_satellite_bounds.size == Vector2.ZERO:
		safe_satellite_bounds = Rect2(-DEFAULT_SATELLITE_VISUAL_SIZE * 0.5, DEFAULT_SATELLITE_VISUAL_SIZE)

	var edge_gap := maxf(MIN_EDGE_GAP, safe_ship_bounds.size.x * EDGE_GAP_RATIO)
	var position_y := safe_ship_bounds.get_center().y - safe_satellite_bounds.get_center().y

	if position_index == 0:
		var left_x := safe_ship_bounds.position.x - edge_gap - safe_satellite_bounds.size.x - safe_satellite_bounds.position.x
		return Vector2(left_x, position_y)

	var right_x := safe_ship_bounds.end.x + edge_gap - safe_satellite_bounds.position.x
	return Vector2(right_x, position_y)

func _get_ship_visual_bounds_local() -> Rect2:
	if not _sprite or _sprite.texture == null:
		return Rect2()

	var visible_rect := _get_texture_visible_rect(_sprite.texture)
	var texture_size := _sprite.texture.get_size()
	var top_left := _sprite.offset
	if _sprite.centered:
		top_left -= texture_size * 0.5

	var raw_rect := Rect2(top_left + visible_rect.position, visible_rect.size)
	return _transform_rect(raw_rect, _sprite.transform)

func _get_satellite_visual_bounds_local(satellite: Node2D) -> Rect2:
	if satellite.has_method("get_visual_bounds_local"):
		var bounds: Variant = satellite.call("get_visual_bounds_local")
		if bounds is Rect2:
			return bounds
	return Rect2(-DEFAULT_SATELLITE_VISUAL_SIZE * 0.5, DEFAULT_SATELLITE_VISUAL_SIZE)

func _get_texture_visible_rect(texture: Texture2D) -> Rect2:
	var texture_size := texture.get_size()
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2(Vector2.ZERO, texture_size)

	var used_rect := image.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return Rect2(Vector2.ZERO, texture_size)

	return Rect2(Vector2(used_rect.position), Vector2(used_rect.size))

func _transform_rect(rect: Rect2, transform_2d: Transform2D) -> Rect2:
	var corners := PackedVector2Array([
		transform_2d * rect.position,
		transform_2d * Vector2(rect.position.x + rect.size.x, rect.position.y),
		transform_2d * Vector2(rect.position.x, rect.position.y + rect.size.y),
		transform_2d * (rect.position + rect.size)
	])

	var min_x := corners[0].x
	var max_x := corners[0].x
	var min_y := corners[0].y
	var max_y := corners[0].y

	for point in corners:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)

	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
