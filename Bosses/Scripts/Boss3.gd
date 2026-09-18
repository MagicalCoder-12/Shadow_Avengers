extends BossBase
class_name Boss3


const HOMING_BULLET_SCENE := preload("res://Bullet/Boss_bullet/homing_bullet.tscn")
const ENERGY_BALL_SCENE := preload("res://Bullet/Boss_bullet/energy_ball.tscn")
const HELL_PATTERN_SCENE := preload("res://Bullet/Boss_bullet/hell_pattern.tscn")
const MUZZLE_FLASH_SCENE := preload("res://Bosses/muzzle_flash.tscn")

@export var boss_id: String = "Boss3"
@export var stage_2_max_health: int = 80000
@export var pattern_pause_short: float = 0.18
@export var pattern_pause_medium: float = 0.38
@export var hover_width: float = 300.0
@export var hover_height: float = 86.0
@export var phase_2_texture: Texture2D

func _ready() -> void:
	max_health = 40000
	phase_2_health_threshold = 20000
	descent_target_y = 560.0
	descent_speed = 375.0
	move_speed_phase_1 = 280.0
	move_speed_phase_2 = 360.0
	attack_interval_phase_1 = 1.95
	attack_interval_phase_2 = 1.2
	phase_transition_duration = 1.55
	screen_margin = 150.0
	contact_damage = 1
	boss_score_value = 0
	boss_bullet_damage_phase_1 = 1
	boss_bullet_damage_phase_2 = 1
	super._ready()

func get_enemy_type_id() -> String:
	return boss_id

func get_phase_1_pattern_ids() -> Array[StringName]:
	return [&"radial_gap_burst", &"cross_lane_punish"]

func get_phase_2_pattern_ids() -> Array[StringName]:
	return [&"double_spiral_sniper", &"collapsing_circle"]

func execute_pattern(pattern_id: StringName) -> void:
	match pattern_id:
		&"radial_gap_burst":
			_pattern_phase_1_radial_gap_burst()
		&"cross_lane_punish":
			_pattern_phase_1_cross_lane_punish()
		&"double_spiral_sniper":
			_pattern_phase_2_double_spiral_sniper()
		&"collapsing_circle":
			_pattern_phase_2_collapsing_circle()
		_:
			push_warning("Boss3 received unknown pattern '%s'." % String(pattern_id))
			finish_pattern_execution()

func get_movement_target(_delta: float) -> Vector2:
	var viewport_rect := get_viewport().get_visible_rect()
	var center := Vector2(
		viewport_rect.position.x + viewport_rect.size.x * 0.5,
		viewport_rect.position.y + descent_target_y
	)
	var time := Time.get_ticks_msec() * 0.001
	var width := hover_width if current_phase == BossPhase.PHASE_1 else hover_width + 55.0
	var height := hover_height if current_phase == BossPhase.PHASE_1 else hover_height + 26.0
	return center + Vector2(cos(time * 0.72) * width, sin(time * 1.32) * height)

func on_phase_1_started() -> void:
	_show_muzzle_flash(_get_center_fire_position())

func on_phase_2_started() -> void:
	if phase_2_texture and boss_sprite is Sprite2D:
		(boss_sprite as Sprite2D).texture = phase_2_texture
	_show_muzzle_flash(_get_center_fire_position())

func _pattern_phase_1_radial_gap_burst() -> void:
	var fire_position := _get_center_fire_position()
	var player_angle := _get_player_direction(fire_position).angle()
	var bullet_count := 16
	var safe_gap_half_angle := 0.42

	await _show_muzzle_flash_and_wait(fire_position)
	for bullet_index in range(bullet_count):
		var angle := TAU * float(bullet_index) / float(bullet_count)
		var angle_delta := wrapf(angle - player_angle, -PI, PI)
		if abs(angle_delta) < safe_gap_half_angle:
			continue
		spawn_bullet(HELL_PATTERN_SCENE, fire_position, Vector2.RIGHT.rotated(angle), 600.0, boss_bullet_damage_phase_1, 5.2)
	if await _await_boss_timer(pattern_pause_short):
		finish_pattern_execution()

func _pattern_phase_1_cross_lane_punish() -> void:
	var side_markers := _get_side_markers()
	if side_markers.size() < 2:
		finish_pattern_execution()
		return

	for marker in side_markers:
		var fire_position := marker.global_position
		await _show_muzzle_flash_and_wait(fire_position)
		var vertical_direction := Vector2.DOWN.rotated(-0.08 if marker.name == "Left" else 0.08)
		spawn_bullet(HELL_PATTERN_SCENE, fire_position, vertical_direction, 680.0, boss_bullet_damage_phase_1, 4.8)
		spawn_bullet(HELL_PATTERN_SCENE, fire_position, vertical_direction.rotated(0.12 if marker.name == "Left" else -0.12), 680.0, boss_bullet_damage_phase_1, 4.8)

	if not await _await_boss_timer(pattern_pause_medium):
		finish_pattern_execution()
		return
	var center_fire_position := _get_center_fire_position()
	await _show_muzzle_flash_and_wait(center_fire_position)
	if not is_inside_tree():
		finish_pattern_execution()
		return
	var punish_direction := _get_player_direction(center_fire_position)
	var punish_ball := spawn_bullet(ENERGY_BALL_SCENE, center_fire_position, punish_direction, 390.0, boss_bullet_damage_phase_1, 4.6)
	if punish_ball and punish_ball.has_method("set_speed"):
		punish_ball.set_speed(390.0)
	finish_pattern_execution()

func _pattern_phase_2_double_spiral_sniper() -> void:
	var fire_position := _get_center_fire_position()
	var base_angle := _get_player_direction(fire_position).angle()

	for step in range(8):
		await _show_muzzle_flash_and_wait(fire_position)
		if not is_inside_tree(): break
		var rotation_offset := step * 0.24
		var spiral_a := Vector2.RIGHT.rotated(base_angle + rotation_offset)
		var spiral_b := Vector2.RIGHT.rotated(base_angle + PI + rotation_offset)
		spawn_bullet(HELL_PATTERN_SCENE, fire_position, spiral_a, 650.0 + step * 14.0, boss_bullet_damage_phase_2, 5.4)
		spawn_bullet(HELL_PATTERN_SCENE, fire_position, spiral_b, 650.0 + step * 14.0, boss_bullet_damage_phase_2, 5.4)
		if step == 2 or step == 5:
			var snipe_direction := _get_player_direction(fire_position)
			var homing := spawn_bullet(HOMING_BULLET_SCENE, fire_position, snipe_direction, 490.0, boss_bullet_damage_phase_2, 4.2)
			if homing and homing.has_method("set_turn_rate"):
				homing.set_turn_rate(0.024)
		if not await _await_boss_timer(0.1): break
	finish_pattern_execution()

func _pattern_phase_2_collapsing_circle() -> void:
	var fire_position := _get_center_fire_position()
	var player_angle := _get_player_direction(fire_position).angle()
	var outer_bullets := 12
	var inner_bullets := 10
	var safe_gap_half_angle := 0.3

	await _show_muzzle_flash_and_wait(fire_position)
	for bullet_index in range(outer_bullets):
		var angle := TAU * float(bullet_index) / float(outer_bullets)
		var angle_delta := wrapf(angle - player_angle, -PI, PI)
		if abs(angle_delta) < safe_gap_half_angle:
			continue
		spawn_bullet(HELL_PATTERN_SCENE, fire_position, Vector2.RIGHT.rotated(angle), 520.0, boss_bullet_damage_phase_2, 5.6)

	if not await _await_boss_timer(pattern_pause_short):
		finish_pattern_execution()
		return

	for bullet_index in range(inner_bullets):
		var angle := TAU * float(bullet_index) / float(inner_bullets) + 0.16
		var angle_delta := wrapf(angle - player_angle, -PI, PI)
		if abs(angle_delta) < safe_gap_half_angle * 0.85:
			continue
		spawn_bullet(HELL_PATTERN_SCENE, fire_position, Vector2.RIGHT.rotated(angle), 780.0, boss_bullet_damage_phase_2, 4.7)

	finish_pattern_execution()

func _get_center_fire_position() -> Vector2:
	var markers := get_valid_markers()
	for marker in markers:
		if marker.name == "Center":
			return marker.global_position
	if not markers.is_empty():
		return markers[0].global_position
	return global_position

func _get_side_markers() -> Array[Marker2D]:
	var side_markers: Array[Marker2D] = []
	for marker in get_valid_markers():
		if marker.name == "Left" or marker.name == "Right":
			side_markers.append(marker)
	if side_markers.is_empty():
		for marker in get_valid_markers():
			side_markers.append(marker)
	return side_markers

func _get_player_position() -> Vector2:
	var player := get_player()
	if player:
		return player.global_position
	return global_position + Vector2.DOWN * 720.0

func _get_player_direction(from_position: Vector2) -> Vector2:
	var direction := (_get_player_position() - from_position).normalized()
	if direction == Vector2.ZERO:
		return Vector2.DOWN
	return direction

func _show_muzzle_flash(flash_position: Vector2) -> void:
	spawn_effect(MUZZLE_FLASH_SCENE, flash_position)

func _show_muzzle_flash_and_wait(flash_position: Vector2) -> void:
	await spawn_effect_and_wait(MUZZLE_FLASH_SCENE, flash_position)
