extends BossBase
class_name Boss1


const HOMING_BULLET_SCENE := preload("res://Bullet/Boss_bullet/homing_bullet.tscn")
const ENERGY_BALL_SCENE := preload("res://Bullet/Boss_bullet/energy_ball.tscn")
const HELL_PATTERN_SCENE := preload("res://Bullet/Boss_bullet/hell_pattern.tscn")
const MUZZLE_FLASH_SCENE := preload("res://Bosses/muzzle_flash.tscn")

@export var boss_id: String = "Boss1"
@export var pattern_pause_short: float = 0.18
@export var pattern_pause_medium: float = 0.35
@export var hover_width: float = 220.0
@export var hover_height: float = 56.0
@export var phase_2_texture: Texture2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	super._ready()

func get_enemy_type_id() -> String:
	return boss_id

func get_phase_1_pattern_ids() -> Array[StringName]:
	return [&"fan_burst", &"aimed_dual"]

func get_phase_2_pattern_ids() -> Array[StringName]:
	return [&"wide_fan_stagger", &"twin_spiral"]

func execute_pattern(pattern_id: StringName) -> void:
	match pattern_id:
		&"fan_burst":
			_pattern_phase_1_fan_burst()
		&"aimed_dual":
			_pattern_phase_1_aimed_dual()
		&"wide_fan_stagger":
			_pattern_phase_2_wide_fan_stagger()
		&"twin_spiral":
			_pattern_phase_2_twin_spiral()
		_:
			push_warning("Boss1 received unknown pattern '%s'." % String(pattern_id))
			finish_pattern_execution()

func get_movement_target(_delta: float) -> Vector2:
	var viewport_rect := get_viewport().get_visible_rect()
	var center := Vector2(
		viewport_rect.position.x + viewport_rect.size.x * 0.5,
		viewport_rect.position.y + descent_target_y
	)
	var time := Time.get_ticks_msec() * 0.001
	var width := hover_width if current_phase == BossPhase.PHASE_1 else hover_width + 40.0
	var height := hover_height if current_phase == BossPhase.PHASE_1 else hover_height + 18.0
	return center + Vector2(cos(time * 0.75) * width, sin(time * 1.15) * height)

func on_phase_1_started() -> void:
	_show_muzzle_flash(_get_primary_marker_position())

func on_phase_2_started() -> void:
	if phase_2_texture and boss_sprite is Sprite2D:
		(boss_sprite as Sprite2D).texture = phase_2_texture
	_show_muzzle_flash(_get_primary_marker_position())

func _pattern_phase_1_fan_burst() -> void:
	var marker := _get_primary_marker_position()
	var base_direction := _get_player_direction(marker)
	var angles := [-0.46, -0.23, 0.0, 0.23, 0.46]

	for volley in range(3):
		await _show_muzzle_flash_and_wait(marker)
		if not is_inside_tree(): break
		for offset in angles:
			var direction := base_direction.rotated(offset)
			spawn_bullet(HELL_PATTERN_SCENE, marker, direction, 520.0, boss_bullet_damage_phase_1, 5.0)
		if volley < 2:
			if not await _await_boss_timer(pattern_pause_short): break
	finish_pattern_execution()

func _pattern_phase_1_aimed_dual() -> void:
	var markers := get_valid_markers()
	if markers.is_empty():
		finish_pattern_execution()
		return

	var target_position := _get_player_position()
	var ordered_markers: Array[Marker2D] = []
	for marker in markers:
		if marker.name == "Left" or marker.name == "Right":
			ordered_markers.append(marker)
	if ordered_markers.is_empty():
		ordered_markers = markers

	for marker in ordered_markers:
		var fire_position := marker.global_position
		var aim_direction := _get_direction_to_target(fire_position, target_position)
		await _show_muzzle_flash_and_wait(fire_position)
		if not is_inside_tree(): break
		var bullet := spawn_bullet(HOMING_BULLET_SCENE, fire_position, aim_direction, 430.0, boss_bullet_damage_phase_1, 4.0)
		if bullet and bullet.has_method("set_turn_rate"):
			bullet.set_turn_rate(0.02)
		if not await _await_boss_timer(pattern_pause_medium): break
	finish_pattern_execution()

func _pattern_phase_2_wide_fan_stagger() -> void:
	var marker := _get_primary_marker_position()
	var base_direction := _get_player_direction(marker)
	var angles := [-0.55, -0.36, -0.18, 0.0, 0.18, 0.36, 0.55]

	for wave in range(2):
		await _show_muzzle_flash_and_wait(marker)
		if not is_inside_tree(): break
		for offset in angles:
			var direction := base_direction.rotated(offset + float(wave) * 0.05)
			spawn_bullet(HELL_PATTERN_SCENE, marker, direction, 660.0, boss_bullet_damage_phase_2, 5.5)
		if not await _await_boss_timer(pattern_pause_medium): break
	finish_pattern_execution()

func _pattern_phase_2_twin_spiral() -> void:
	var marker := _get_primary_marker_position()
	var base_angle := _get_player_direction(marker).angle()
	var spiral_pairs := 6

	for step in range(spiral_pairs):
		await _show_muzzle_flash_and_wait(marker)
		if not is_inside_tree(): break
		var rotation_offset := step * 0.22
		var direction_a := Vector2.RIGHT.rotated(base_angle + rotation_offset)
		var direction_b := Vector2.RIGHT.rotated(base_angle + PI + rotation_offset)
		spawn_bullet(HELL_PATTERN_SCENE, marker, direction_a, 620.0 + step * 18.0, boss_bullet_damage_phase_2, 5.5)
		spawn_bullet(HELL_PATTERN_SCENE, marker, direction_b, 620.0 + step * 18.0, boss_bullet_damage_phase_2, 5.5)
		if step % 2 == 1:
			var player_direction := _get_player_direction(marker)
			var energy_ball := spawn_bullet(ENERGY_BALL_SCENE, marker, player_direction, 420.0, boss_bullet_damage_phase_2, 4.5)
			if energy_ball and energy_ball.has_method("set_speed"):
				energy_ball.set_speed(420.0)
		if not await _await_boss_timer(0.11): break
	finish_pattern_execution()

func _get_primary_marker_position() -> Vector2:
	var markers := get_valid_markers()
	for marker in markers:
		if marker.name == "Center":
			return marker.global_position
	if not markers.is_empty():
		return markers[0].global_position
	return global_position

func _get_player_position() -> Vector2:
	var player := get_player()
	if player:
		return player.global_position
	return global_position + Vector2.DOWN * 600.0

func _get_player_direction(from_position: Vector2) -> Vector2:
	return _get_direction_to_target(from_position, _get_player_position())

func _get_direction_to_target(from_position: Vector2, target_position: Vector2) -> Vector2:
	var direction := (target_position - from_position).normalized()
	if direction == Vector2.ZERO:
		return Vector2.DOWN
	return direction

func _show_muzzle_flash(flash_position: Vector2) -> void:
	spawn_effect(MUZZLE_FLASH_SCENE, flash_position)

func _show_muzzle_flash_and_wait(flash_position: Vector2) -> void:
	await spawn_effect_and_wait(MUZZLE_FLASH_SCENE, flash_position)
