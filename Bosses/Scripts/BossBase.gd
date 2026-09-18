extends Area2D
class_name BossBase

const FormationEnums := preload("res://EnemyManager/Scripts/formation_enums.gd")

signal boss_defeated
signal phase_changed(new_phase: int)
signal descent_completed
signal enemy_died(payload: Dictionary)
signal pattern_execution_finished

enum BossPhase {
	DESCENT,
	PHASE_1,
	TRANSITION,
	PHASE_2,
	DEFEATED
}

const PHASE_TRANSITION_EFFECT_SCENE := preload("res://Bosses/phase_transition_effect.tscn")
const HOMING_BULLET_SCENE_PATH := "res://Bullet/Boss_bullet/homing_bullet.tscn"

@export var max_health: int = 30000
@export var phase_2_health_threshold: int = 0
@export var descent_target_y: float = 600.0
@export var descent_speed: float = 500.0
@export var move_speed_phase_1: float = 300.0
@export var move_speed_phase_2: float = 350.0
@export var attack_interval_phase_1: float = 2.2
@export var attack_interval_phase_2: float = 1.4
@export var phase_transition_duration: float = 1.5
@export var screen_margin: float = 96.0
@export var contact_damage: int = 1
@export var boss_score_value: int = 0
@export var shadow_tint: Color = Color(0.55, 0.4, 0.95, 1.0)
@export var boss_bullet_damage_phase_1: int = 1
@export var boss_bullet_damage_phase_2: int = 1

@onready var attack_timer: Timer = $AttackTimer
@onready var boss_sprite: Node2D = $Boss
@onready var health_bar: TextureProgressBar = $HealthBar
@onready var boss_death_particles: CPUParticles2D = $BossDeathParticles
@onready var boss_death: AudioStreamPlayer = $BossDeath
@onready var phase_change: AudioStreamPlayer2D = $PhaseChange

var current_phase: int = BossPhase.DESCENT
var current_health: int = 0
var has_completed_descent: bool = false
var is_invincible: bool = false

var _death_sequence_started: bool = false
var _phase_transition_started: bool = false
var _is_shadow_form_active: bool = false
var _last_pattern_id: StringName = &""
var _repeat_count: int = 0
var _pattern_execution_in_progress: bool = false
var _active_homing_bullet: Area2D = null

func _ready() -> void:
	if not _validate_required_nodes():
		_disable_boss()
		return

	_normalize_exported_values()
	_apply_difficulty_scaling()
	current_health = max_health
	current_phase = BossPhase.DESCENT
	_update_health_bar()
	health_bar.show()

	add_to_group(GameManager.GROUP_BOSS)
	_connect_core_signals()
	attack_timer.stop()
	attack_timer.wait_time = attack_interval_phase_1

func _physics_process(delta: float) -> void:
	match current_phase:
		BossPhase.DESCENT:
			_handle_descent(delta)
		BossPhase.PHASE_1, BossPhase.PHASE_2:
			_handle_movement(delta)
		_:
			return

func _validate_required_nodes() -> bool:
	var required_ok := true
	if not attack_timer:
		push_error("BossBase requires an AttackTimer node.")
		required_ok = false
	if not boss_sprite:
		push_error("BossBase requires a Boss node.")
		required_ok = false
	if not health_bar:
		push_error("BossBase requires a HealthBar node.")
		required_ok = false
	if not boss_death_particles:
		push_error("BossBase requires a BossDeathParticles node.")
		required_ok = false
	if not boss_death:
		push_error("BossBase requires a BossDeath node.")
		required_ok = false
	if not phase_change:
		push_error("BossBase requires a PhaseChange node.")
		required_ok = false
	return required_ok

func _disable_boss() -> void:
	set_physics_process(false)
	set_process(false)
	if attack_timer:
		attack_timer.stop()

func _normalize_exported_values() -> void:
	max_health = max(1, max_health)
	if phase_2_health_threshold <= 0 or phase_2_health_threshold >= max_health:
		phase_2_health_threshold = int(round(max_health * 0.5))

	descent_speed = max(1.0, descent_speed)
	move_speed_phase_1 = max(1.0, move_speed_phase_1)
	move_speed_phase_2 = max(1.0, move_speed_phase_2)
	attack_interval_phase_1 = max(0.1, attack_interval_phase_1)
	attack_interval_phase_2 = max(0.1, attack_interval_phase_2)
	phase_transition_duration = max(0.1, phase_transition_duration)
	screen_margin = max(0.0, screen_margin)
	contact_damage = max(0, contact_damage)
	boss_bullet_damage_phase_1 = max(1, boss_bullet_damage_phase_1)
	boss_bullet_damage_phase_2 = max(1, boss_bullet_damage_phase_2)

func _connect_core_signals() -> void:
	if not attack_timer.timeout.is_connected(_on_attack_timer_timeout):
		attack_timer.timeout.connect(_on_attack_timer_timeout)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func _apply_difficulty_scaling() -> void:
	var health_multiplier := _get_boss_health_multiplier()
	var attack_interval_multiplier := _get_boss_attack_interval_multiplier()
	if health_multiplier != 1.0:
		max_health = max(1, int(round(max_health * health_multiplier)))
		phase_2_health_threshold = max(1, int(round(phase_2_health_threshold * health_multiplier)))
	if attack_interval_multiplier != 1.0:
		attack_interval_phase_1 = max(0.1, attack_interval_phase_1 * attack_interval_multiplier)
		attack_interval_phase_2 = max(0.1, attack_interval_phase_2 * attack_interval_multiplier)

func _get_boss_health_multiplier() -> float:
	if not GameManager:
		return 1.0
	match GameManager.current_difficulty:
		FormationEnums.DifficultyLevel.NORMAL:
			return 1.3
		FormationEnums.DifficultyLevel.HARD:
			return 1.65
		FormationEnums.DifficultyLevel.NIGHTMARE:
			return 2.0
		_:
			return 1.0

func _get_boss_attack_interval_multiplier() -> float:
	if not GameManager:
		return 1.0
	match GameManager.current_difficulty:
		FormationEnums.DifficultyLevel.NORMAL:
			return 0.9
		FormationEnums.DifficultyLevel.HARD:
			return 0.78
		FormationEnums.DifficultyLevel.NIGHTMARE:
			return 0.68
		_:
			return 1.0

func _handle_descent(delta: float) -> void:
	var viewport_rect := get_viewport().get_visible_rect()
	var target_y := viewport_rect.position.y + descent_target_y
	global_position.y = min(global_position.y + descent_speed * delta, target_y)
	global_position.x = clamp(global_position.x, viewport_rect.position.x + screen_margin, viewport_rect.position.x + viewport_rect.size.x - screen_margin)

	if global_position.y >= target_y:
		_complete_descent()

func _complete_descent() -> void:
	if has_completed_descent:
		return

	has_completed_descent = true
	current_phase = BossPhase.PHASE_1
	_last_pattern_id = &""
	_repeat_count = 0
	attack_timer.wait_time = attack_interval_phase_1
	attack_timer.start()
	descent_completed.emit()
	on_phase_1_started()

func _handle_movement(delta: float) -> void:
	var target_position := get_movement_target(delta)
	var move_speed := move_speed_phase_2 if current_phase == BossPhase.PHASE_2 else move_speed_phase_1
	global_position = global_position.move_toward(target_position, move_speed * delta)
	global_position = _clamp_to_screen(global_position)

func _clamp_to_screen(pos: Vector2) -> Vector2:
	var viewport_rect := get_viewport().get_visible_rect()
	pos.x = clamp(pos.x, viewport_rect.position.x + screen_margin, viewport_rect.position.x + viewport_rect.size.x - screen_margin)
	pos.y = clamp(pos.y, viewport_rect.position.y + screen_margin, viewport_rect.position.y + viewport_rect.size.y - screen_margin)
	return pos

func _on_attack_timer_timeout() -> void:
	if current_phase != BossPhase.PHASE_1 and current_phase != BossPhase.PHASE_2:
		return
	if _death_sequence_started or current_phase == BossPhase.TRANSITION:
		return

	var patterns := get_phase_pattern_ids()
	if patterns.is_empty():
		return

	var pattern_id := pick_pattern(patterns)
	if pattern_id == StringName():
		return

	attack_timer.stop()
	_pattern_execution_in_progress = true
	execute_pattern(pattern_id)
	if _pattern_execution_in_progress:
		await pattern_execution_finished

	if current_phase == BossPhase.PHASE_1 or current_phase == BossPhase.PHASE_2:
		attack_timer.wait_time = attack_interval_phase_2 if current_phase == BossPhase.PHASE_2 else attack_interval_phase_1
		attack_timer.start()

func get_phase_pattern_ids() -> Array[StringName]:
	if current_phase == BossPhase.PHASE_2:
		return get_phase_2_pattern_ids()
	return get_phase_1_pattern_ids()

func take_damage(amount: int) -> void:
	if amount <= 0 or _death_sequence_started or is_invincible:
		return

	current_health = max(0, current_health - amount)
	_update_health_bar()

	if current_phase == BossPhase.PHASE_1 and current_health <= phase_2_health_threshold:
		current_health = max(1, current_health)
		_update_health_bar()
		_start_phase_transition()
		return

	if current_health <= 0:
		_begin_death_sequence()

func set_invincible(active: bool) -> void:
	is_invincible = active

func _start_phase_transition() -> void:
	if _phase_transition_started or current_phase != BossPhase.PHASE_1 or _death_sequence_started:
		return

	_phase_transition_started = true
	current_phase = BossPhase.TRANSITION
	attack_timer.stop()
	set_invincible(true)
	finish_pattern_execution()

	if phase_change:
		phase_change.play()

	_apply_shadow_visuals()
	spawn_effect(PHASE_TRANSITION_EFFECT_SCENE, global_position)
	_finish_phase_transition()

func _finish_phase_transition() -> void:
	await get_tree().create_timer(phase_transition_duration).timeout
	if not is_inside_tree() or _death_sequence_started:
		return

	current_phase = BossPhase.PHASE_2
	_is_shadow_form_active = true
	_last_pattern_id = &""
	_repeat_count = 0
	set_invincible(false)
	attack_timer.wait_time = attack_interval_phase_2
	attack_timer.start()
	phase_changed.emit(current_phase)
	on_phase_2_started()

func _apply_shadow_visuals() -> void:
	if boss_sprite:
		boss_sprite.modulate = shadow_tint

func _begin_death_sequence() -> void:
	if _death_sequence_started:
		return

	_death_sequence_started = true
	current_phase = BossPhase.DEFEATED
	attack_timer.stop()
	set_invincible(true)
	finish_pattern_execution()
	_emit_death_effects()

	var payload := build_enemy_died_payload()
	enemy_died.emit(payload)
	boss_defeated.emit()
	on_boss_defeated()

	var cleanup_delay := _get_death_cleanup_delay()
	if cleanup_delay > 0.0:
		await get_tree().create_timer(cleanup_delay).timeout

	if is_inside_tree():
		queue_free()

func _emit_death_effects() -> void:
	if boss_death_particles:
		boss_death_particles.emitting = false
		boss_death_particles.restart()
		boss_death_particles.emitting = true
	if boss_death:
		boss_death.play()

func _get_death_cleanup_delay() -> float:
	var delay := 0.0
	if boss_death_particles:
		delay = max(delay, boss_death_particles.lifetime)
	if boss_death and boss_death.stream:
		delay = max(delay, boss_death.stream.get_length())
	return delay

func _update_health_bar() -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health

func _on_area_entered(area: Area2D) -> void:
	if not area:
		return

	if area.is_in_group("player_bullets"):
		var damage_amount := _resolve_damage(area)
		take_damage(damage_amount)
		area.call_deferred("queue_free")
		return

	if contact_damage > 0 and area.is_in_group("Player") and area.has_method("damage"):
		area.damage(contact_damage)

func _resolve_damage(area: Area2D) -> int:
	if area.has_method("get_damage"):
		return max(1, int(area.get_damage()))
	for property in area.get_property_list():
		if property.get("name", "") == "damage":
			return max(1, int(area.get("damage")))
	return 1

func spawn_bullet(scene: PackedScene, spawn_position: Vector2, direction: Vector2, speed: float, damage: int, lifetime: float = 6.0) -> Area2D:
	if not scene or not scene.can_instantiate():
		push_warning("BossBase.spawn_bullet called with an invalid scene.")
		return null
	if _is_homing_bullet_scene(scene) and _has_active_homing_bullet():
		return null

	var bullet := scene.instantiate() as Area2D
	if not bullet:
		push_warning("BossBase.spawn_bullet could not instantiate an Area2D bullet.")
		return null

	var normalized_direction := direction.normalized()
	if normalized_direction == Vector2.ZERO:
		normalized_direction = Vector2.DOWN

	bullet.global_position = spawn_position
	bullet.global_rotation = normalized_direction.angle()
	if bullet.has_method("set_direction"):
		bullet.set_direction(normalized_direction)
	elif _has_property(bullet, "direction"):
		bullet.set("direction", normalized_direction)

	if bullet.has_method("set_speed"):
		bullet.set_speed(speed)
	elif _has_property(bullet, "speed"):
		bullet.set("speed", speed)

	if bullet.has_method("set_damage"):
		bullet.set_damage(damage)
	elif _has_property(bullet, "damage"):
		bullet.set("damage", damage)

	if bullet.has_method("set_lifetime"):
		bullet.set_lifetime(lifetime)
	elif _has_property(bullet, "lifetime"):
		bullet.set("lifetime", lifetime)

	SceneSpawnService.spawn_child(bullet)
	if _is_homing_bullet_scene(scene):
		_track_homing_bullet(bullet)
	return bullet

func spawn_effect(scene: PackedScene, effect_position: Vector2) -> Node:
	if not scene or not scene.can_instantiate():
		return null

	var effect := scene.instantiate()
	if effect is Node2D:
		effect.global_position = effect_position
	return SceneSpawnService.spawn_child(effect)

func spawn_effect_and_wait(scene: PackedScene, effect_position: Vector2) -> void:
	var effect := spawn_effect(scene, effect_position)
	if effect and effect.has_signal("effect_finished"):
		await effect.effect_finished

func get_player() -> Node:
	return get_tree().get_first_node_in_group("Player")

func get_valid_markers() -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	for marker_name in [&"Left", &"Center", &"Right"]:
		var marker := boss_sprite.get_node_or_null(String(marker_name)) as Marker2D
		if marker:
			markers.append(marker)
	return markers

func pick_pattern(patterns: Array[StringName]) -> StringName:
	if patterns.is_empty():
		return StringName()

	var available_patterns := patterns.duplicate()
	if available_patterns.size() > 1 and _repeat_count >= 2:
		available_patterns = available_patterns.filter(func(candidate_pattern_id: StringName) -> bool:
			return candidate_pattern_id != _last_pattern_id
		)
		if available_patterns.is_empty():
			available_patterns = patterns.duplicate()

	var pattern_id: StringName = available_patterns[randi() % available_patterns.size()]
	if pattern_id == _last_pattern_id:
		_repeat_count += 1
	else:
		_last_pattern_id = pattern_id
		_repeat_count = 1
	return pattern_id

func build_enemy_died_payload() -> Dictionary:
	return {
		"enemy_type": get_enemy_type_id(),
		"is_boss": true,
		"base_score": boss_score_value,
		"is_shadow_enemy": _is_shadow_form_active,
		"shadow_score_multiplier": 1.0,
		"global_position": global_position,
	}

func get_enemy_type_id() -> String:
	if not String(name).is_empty():
		return String(name)
	return "BossBase"

func get_phase_1_pattern_ids() -> Array[StringName]:
	return []

func get_phase_2_pattern_ids() -> Array[StringName]:
	return []

func execute_pattern(pattern_id: StringName) -> void:
	push_warning("BossBase.execute_pattern must be overridden. Received pattern '%s'." % String(pattern_id))
	finish_pattern_execution()

func get_movement_target(_delta: float) -> Vector2:
	var viewport_rect := get_viewport().get_visible_rect()
	var center := Vector2(
		viewport_rect.position.x + viewport_rect.size.x * 0.5,
		viewport_rect.position.y + descent_target_y
	)
	var time := Time.get_ticks_msec() * 0.001
	var radius_x := 180.0 if current_phase == BossPhase.PHASE_1 else 220.0
	var radius_y := 48.0 if current_phase == BossPhase.PHASE_1 else 72.0
	return center + Vector2(cos(time * 0.9) * radius_x, sin(time * 1.15) * radius_y)

func on_phase_1_started() -> void:
	pass

func on_phase_2_started() -> void:
	pass

func on_boss_defeated() -> void:
	pass

func finish_pattern_execution() -> void:
	if not _pattern_execution_in_progress:
		return
	_pattern_execution_in_progress = false
	pattern_execution_finished.emit()

## Safe timer await — returns true if the boss is still alive and in the tree,
## false if it was freed during the wait (caller should return immediately).
func _await_boss_timer(duration: float) -> bool:
	await get_tree().create_timer(duration).timeout
	return is_inside_tree() and not _death_sequence_started

func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if property.get("name", "") == property_name:
			return true
	return false

func _is_homing_bullet_scene(scene: PackedScene) -> bool:
	return scene.resource_path == HOMING_BULLET_SCENE_PATH

func _has_active_homing_bullet() -> bool:
	if not is_instance_valid(_active_homing_bullet):
		_active_homing_bullet = null
		return false
	if _active_homing_bullet.is_queued_for_deletion():
		_active_homing_bullet = null
		return false
	return _active_homing_bullet.is_inside_tree()

func _track_homing_bullet(bullet: Area2D) -> void:
	_active_homing_bullet = bullet
	var cleanup_callable := Callable(self, "_clear_tracked_homing_bullet")
	if not bullet.tree_exited.is_connected(cleanup_callable):
		bullet.tree_exited.connect(cleanup_callable, CONNECT_ONE_SHOT)

func _clear_tracked_homing_bullet() -> void:
	_active_homing_bullet = null
