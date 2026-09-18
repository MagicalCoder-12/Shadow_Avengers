extends BossBase
class_name Boss2


const HOMING_BULLET_SCENE := preload("res://Bullet/Boss_bullet/homing_bullet.tscn")
const ENERGY_BALL_SCENE := preload("res://Bullet/Boss_bullet/energy_ball.tscn")
const HELL_PATTERN_SCENE := preload("res://Bullet/Boss_bullet/hell_pattern.tscn")
const MUZZLE_FLASH_SCENE := preload("res://Bosses/muzzle_flash.tscn")

@export var boss_id: String = "Boss2"
@export var stage_2_max_health: int = 80000
@export var phase_2_texture: Texture2D
@export var pattern_pause_short: float = 0.22
@export var pattern_pause_medium: float = 0.45
@export var hover_width: float = 260.0
@export var hover_height: float = 78.0

func _ready() -> void:
	super._ready()

func get_enemy_type_id() -> String:
	return boss_id

func get_phase_1_pattern_ids() -> Array[StringName]:
	return [&"arc_volley", &"orb_barrage"]

func get_phase_2_pattern_ids() -> Array[StringName]:
	return [&"split_ring", &"hunter_crossfire"]

func execute_pattern(pattern_id: StringName) -> void:
	match pattern_id:
		&"arc_volley":
			_pattern_phase_1_arc_volley()
		&"orb_barrage":
			_pattern_phase_1_orb_barrage()
		&"split_ring":
			_pattern_phase_2_split_ring()
		&"hunter_crossfire":
			_pattern_phase_2_hunter_crossfire()
		_:
			push_warning("Boss2 received unknown pattern '%s'." % String(pattern_id))
			finish_pattern_execution()

func get_movement_target(_delta: float) -> Vector2:
	var viewport_rect := get_viewport().get_visible_rect()
	var center := Vector2(
		viewport_rect.position.x + viewport_rect.size.x * 0.5,
		viewport_rect.position.y + descent_target_y
	)
	var time := Time.get_ticks_msec() * 0.001
	var width := hover_width if current_phase == BossPhase.PHASE_1 else hover_width + 70.0
	var height := hover_height if current_phase == BossPhase.PHASE_1 else hover_height + 22.0
	return center + Vector2(sin(time * 0.9) * width, cos(time * 1.45) * height)

func on_phase_1_started() -> void:
	_show_muzzle_flash(_get_center_fire_position())

func on_phase_2_started() -> void:
	if boss_sprite is Sprite2D:
		if phase_2_texture:
			(boss_sprite as Sprite2D).texture = phase_2_texture
		(boss_sprite as Sprite2D).rotation = 0.04
	_show_muzzle_flash(_get_center_fire_position())

func _pattern_phase_1_arc_volley() -> void:
	var side_markers := _get_side_markers()
	if side_markers.is_empty():
		finish_pattern_execution()
		return

	for burst in range(2):
		for marker in side_markers:
			var fire_position := marker.global_position
			var base_direction := _get_player_direction(fire_position)
			await _show_muzzle_flash_and_wait(fire_position)
			if not is_inside_tree(): break
			for angle_offset in [-0.3, 0.0, 0.3]:
				spawn_bullet(HELL_PATTERN_SCENE, fire_position, base_direction.rotated(angle_offset), 560.0, boss_bullet_damage_phase_1, 5.0)
		if burst < 1:
			if not await _await_boss_timer(pattern_pause_medium): break
	finish_pattern_execution()

func _pattern_phase_1_orb_barrage() -> void:
	var fire_position := _get_center_fire_position()
	var base_direction := _get_player_direction(fire_position)

	for angle_offset in [-0.24, 0.0, 0.24]:
		await _show_muzzle_flash_and_wait(fire_position)
		if not is_inside_tree(): break
		var orb := spawn_bullet(ENERGY_BALL_SCENE, fire_position, base_direction.rotated(angle_offset), 350.0, boss_bullet_damage_phase_1, 5.0)
		if orb and orb.has_method("set_speed"):
			orb.set_speed(350.0)
		if not await _await_boss_timer(pattern_pause_short): break
	finish_pattern_execution()

func _pattern_phase_2_split_ring() -> void:
	var fire_position := _get_center_fire_position()
	var player_angle := _get_player_direction(fire_position).angle()
	var bullet_count := 14
	var safe_gap_half_angle := 0.32

	await _show_muzzle_flash_and_wait(fire_position)
	for bullet_index in range(bullet_count):
		var angle := TAU * float(bullet_index) / float(bullet_count)
		var angle_delta := wrapf(angle - player_angle, -PI, PI)
		if abs(angle_delta) < safe_gap_half_angle:
			continue
		spawn_bullet(HELL_PATTERN_SCENE, fire_position, Vector2.RIGHT.rotated(angle), 690.0, boss_bullet_damage_phase_2, 5.5)

	if not await _await_boss_timer(pattern_pause_medium):
		finish_pattern_execution()
		return
	var follow_up_direction := _get_player_direction(fire_position)
	var energy_ball := spawn_bullet(ENERGY_BALL_SCENE, fire_position, follow_up_direction, 430.0, boss_bullet_damage_phase_2, 4.8)
	if energy_ball and energy_ball.has_method("set_speed"):
		energy_ball.set_speed(430.0)
	finish_pattern_execution()

func _pattern_phase_2_hunter_crossfire() -> void:
	var side_markers := _get_side_markers()
	var center_fire_position := _get_center_fire_position()

	for marker in side_markers:
		var fire_position := marker.global_position
		var aim_direction := _get_player_direction(fire_position)
		await _show_muzzle_flash_and_wait(fire_position)
		if not is_inside_tree(): break
		for volley_index in range(2):
			var homing := spawn_bullet(HOMING_BULLET_SCENE, fire_position, aim_direction.rotated(-0.08 + volley_index * 0.16), 470.0, boss_bullet_damage_phase_2, 4.3)
			if homing and homing.has_method("set_turn_rate"):
				homing.set_turn_rate(0.028)
		if not await _await_boss_timer(pattern_pause_short): break

	await _show_muzzle_flash_and_wait(center_fire_position)
	if not is_inside_tree():
		finish_pattern_execution()
		return
	var center_direction := _get_player_direction(center_fire_position)
	for angle_offset in [-0.28, -0.14, 0.0, 0.14, 0.28]:
		spawn_bullet(HELL_PATTERN_SCENE, center_fire_position, center_direction.rotated(angle_offset), 720.0, boss_bullet_damage_phase_2, 5.0)
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
	return global_position + Vector2.DOWN * 700.0

func _get_player_direction(from_position: Vector2) -> Vector2:
	var direction := (_get_player_position() - from_position).normalized()
	if direction == Vector2.ZERO:
		return Vector2.DOWN
	return direction

func _show_muzzle_flash(flash_position: Vector2) -> void:
	spawn_effect(MUZZLE_FLASH_SCENE, flash_position)

func _show_muzzle_flash_and_wait(flash_position: Vector2) -> void:
	await spawn_effect_and_wait(MUZZLE_FLASH_SCENE, flash_position)
