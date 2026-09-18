extends BossBase
class_name Boss0


signal unlock_shadow_mode

const MUZZLE_FLASH_SCENE := preload("res://Bosses/muzzle_flash.tscn")
const HELL_PATTERN_SCENE := preload("res://Bullet/Boss_bullet/hell_pattern.tscn")

@export var phase_transition_health: int = 4000
@export var projectile_scene: PackedScene
@export var move_speed: float = 400.0
@export var normal_boss_sprite: Texture2D = preload("res://Assets/Boss/oldBossGFX/oldSERPENTARIUS2.png")
@export var shadow_boss_sprite: Texture2D = preload("res://Assets/Boss/oldBossGFX/oldSERPENTARIUS3.png")
@export var orbit_radius: float = 200.0
@export var orbit_vertical_scale: float = 0.3

@onready var nozzle: Node2D = $Boss/Nozzel
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	super._ready()

	if boss_sprite is Sprite2D and normal_boss_sprite:
		(boss_sprite as Sprite2D).texture = normal_boss_sprite
	if animation_player:
		animation_player.play("Idle")

func get_enemy_type_id() -> String:
	return "Boss0"

func get_phase_1_pattern_ids() -> Array[StringName]:
	return [&"converging_storm"]

func get_phase_2_pattern_ids() -> Array[StringName]:
	return [&"spiral_wave"]

func execute_pattern(pattern_id: StringName) -> void:
	match pattern_id:
		&"converging_storm":
			_pattern_p1_converging_storm()
		&"spiral_wave":
			_pattern_p2_spiral_wave()
		_:
			push_warning("Boss0 received unknown pattern '%s'." % String(pattern_id))
			finish_pattern_execution()

func get_movement_target(_delta: float) -> Vector2:
	var viewport_rect := get_viewport().get_visible_rect()
	var center := Vector2(
		viewport_rect.position.x + viewport_rect.size.x * 0.5,
		viewport_rect.position.y + descent_target_y
	)
	var time := Time.get_ticks_msec() * 0.001
	return center + Vector2(
		cos(time) * orbit_radius,
		sin(time * 0.8) * orbit_radius * orbit_vertical_scale
	)

func on_phase_2_started() -> void:
	if boss_sprite is Sprite2D and shadow_boss_sprite:
		(boss_sprite as Sprite2D).texture = shadow_boss_sprite

func on_boss_defeated() -> void:
	unlock_shadow_mode.emit()

func _pattern_p1_converging_storm() -> void:
	if not nozzle:
		finish_pattern_execution()
		return

	var bullet_count := 25
	var start_pos := nozzle.global_position
	await _show_muzzle_flash_and_wait()

	for i in range(bullet_count):
		var angle := i * TAU / float(bullet_count)
		var direction := Vector2(cos(angle), sin(angle))
		spawn_bullet(HELL_PATTERN_SCENE, start_pos, direction, 600.0 + randf_range(-50.0, 50.0), boss_bullet_damage_phase_1, 5.0)

	finish_pattern_execution()

func _pattern_p2_spiral_wave() -> void:
	if not nozzle or not projectile_scene:
		finish_pattern_execution()
		return

	var spiral_arms := 2
	var bullets_per_arm := 3
	var player := get_player()

	for arm in range(spiral_arms):
		await _show_muzzle_flash_and_wait()
		for step in range(bullets_per_arm):
			var angle := (Time.get_ticks_msec() * 0.001 * 1.5) + (arm * PI) + (step * 0.4)
			var direction := Vector2.RIGHT.rotated(angle)
			var bullet := spawn_bullet(projectile_scene, nozzle.global_position, direction, 600.0 + (step * 8.0), boss_bullet_damage_phase_2, 4.0)
			if bullet and bullet.has_method("set_target") and player:
				bullet.set_target(player.global_position)
			if bullet and bullet.has_method("set_turn_rate"):
				bullet.set_turn_rate(0.025)

	if await _await_boss_timer(0.1):
		finish_pattern_execution()

func _show_muzzle_flash() -> void:
	if nozzle:
		spawn_effect(MUZZLE_FLASH_SCENE, nozzle.global_position)

func _show_muzzle_flash_and_wait() -> void:
	if nozzle:
		await spawn_effect_and_wait(MUZZLE_FLASH_SCENE, nozzle.global_position)
