extends RefCounted
class_name EnemyMovementService

const MOVE_FORMATION_HOLD: int = 0
const MOVE_SIDE_TO_SIDE: int = 1
const MOVE_CIRCLE: int = 2
const MOVE_DIVE: int = 3
const MOVE_SWARM_PATTERN: int = 4

var _enemy: Node = null
var _swarm_coherence: float = 0.8
var _circle_radius: float = 80.0
var _circle_angle: float = 0.0
var _swarm_center: Vector2 = Vector2.ZERO

func configure(enemy: Node) -> void:
	_enemy = enemy

func init_movement_patterns() -> void:
	if not _enemy:
		return
	load_attack_settings_from_config()
	load_movement_settings_from_config()
	_circle_angle = 0.0
	_swarm_center = _enemy.formation_position if _enemy.formation_position != Vector2.ZERO else _enemy.global_position

func load_attack_settings_from_config() -> void:
	if not _enemy:
		return
	var attack_settings: Dictionary = GameManager.get_game_settings_section("enemy_attack_settings") if GameManager else {}
	if attack_settings.is_empty():
		return
	_enemy.base_shoot_cooldown = float(attack_settings.get("base_shoot_cooldown", _enemy.base_shoot_cooldown))
	_enemy.min_shoot_cooldown = float(attack_settings.get("min_shoot_cooldown", _enemy.min_shoot_cooldown))
	_enemy.max_shoot_cooldown = float(attack_settings.get("max_shoot_cooldown", _enemy.max_shoot_cooldown))
	var normal_weights: Dictionary = attack_settings.get("normal_pattern_weights", {})
	if not normal_weights.is_empty():
		_enemy.normal_pattern_weights[0] = int(normal_weights.get("single_shot", 60))
		_enemy.normal_pattern_weights[3] = int(normal_weights.get("aimed_shot", 25))
		_enemy.normal_pattern_weights[1] = int(normal_weights.get("spread_shot", 10))
		_enemy.normal_pattern_weights[2] = int(normal_weights.get("burst_shot", 5))
	var shadow_weights: Dictionary = attack_settings.get("shadow_pattern_weights", {})
	if not shadow_weights.is_empty():
		_enemy.shadow_pattern_weights[0] = int(shadow_weights.get("single_shot", 40))
		_enemy.shadow_pattern_weights[3] = int(shadow_weights.get("aimed_shot", 30))
		_enemy.shadow_pattern_weights[1] = int(shadow_weights.get("spread_shot", 20))
		_enemy.shadow_pattern_weights[2] = int(shadow_weights.get("burst_shot", 10))

func load_movement_settings_from_config() -> void:
	if not _enemy:
		return
	var movement_settings: Dictionary = GameManager.get_game_settings_section("movement_settings") if GameManager else {}
	if movement_settings.is_empty():
		return
	_swarm_coherence = float(movement_settings.get("swarm_coherence", _swarm_coherence))
	_circle_radius = float(movement_settings.get("circle_radius", _circle_radius))

# Static cache — avoids per-enemy per-frame group lookups.
static var _cached_player: Player = null

func update_player_reference() -> void:
	if not _enemy:
		return
	# Use cached reference if still valid.
	if is_instance_valid(_cached_player):
		_enemy.player_reference = _cached_player
		return
	# Cache miss — do a single group lookup and store the result.
	var players: Array = _enemy.get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		_cached_player = players[0] as Player
		_enemy.player_reference = _cached_player
	else:
		_cached_player = null
		_enemy.player_reference = null

func handle_entry_shield() -> void:
	if not _enemy:
		return
	if _enemy.time_since_spawn >= _enemy.entry_shadow_shield_time:
		if _enemy.shadow_core_shield and _enemy.shadow_core_shield.visible:
			_enemy.shadow_core_shield.visible = false
			if GameManager.debug_mode:
				print("Entry shield deactivated")
	else:
		if _enemy.shadow_core_shield:
			var alpha: float = (sin(_enemy.time_since_spawn * 5.0) + 1.0) / 2.0
			_enemy.shadow_core_shield.modulate.a = alpha

func handle_movement(delta: float) -> void:
	if not _enemy:
		return
	if _enemy.is_in_entry_phase and _enemy.entry_path.size() > 0:
		follow_entry_path(delta)
	else:
		perform_formation_movement(delta)

func follow_entry_path(delta: float) -> void:
	if not _enemy:
		return
	if _enemy.entry_path_index >= _enemy.entry_path.size():
		reach_formation()
		return
	var target_pos: Vector2 = _enemy.entry_path[_enemy.entry_path_index]
	var direction: Vector2 = (target_pos - _enemy.global_position).normalized()
	var move_speed: float = _enemy.speed * _enemy.entry_speed_multiplier
	_enemy.position += direction * move_speed * delta
	if _enemy.global_position.distance_to(target_pos) < 20.0:
		_enemy.entry_path_index += 1

func reach_formation() -> void:
	if not _enemy:
		return
	_enemy.is_in_entry_phase = false
	_enemy.arrived_at_formation = true
	_enemy.position = _enemy.formation_position
	_enemy.formation_reached.emit()
	if GameManager.debug_mode:
		print("Enemy reached formation position")

func perform_formation_movement(delta: float) -> void:
	if not _enemy:
		return
	match int(_enemy.movement_pattern):
		MOVE_FORMATION_HOLD:
			handle_formation_hold(delta)
		MOVE_SIDE_TO_SIDE:
			handle_side_to_side(delta)
		MOVE_CIRCLE:
			handle_circle_movement(delta)
		MOVE_DIVE:
			handle_dive_pattern(delta)
		MOVE_SWARM_PATTERN:
			handle_swarm_pattern(delta)

func handle_formation_hold(delta: float) -> void:
	if not _enemy:
		return
	var drift := Vector2(
		sin(_enemy.time_since_spawn * 0.5 + _enemy.formation_index) * 5.0,
		cos(_enemy.time_since_spawn * 0.3) * 3.0
	)
	var target: Vector2 = _enemy.formation_position + drift
	_enemy.position = _enemy.position.lerp(target, 2.0 * delta)

func handle_side_to_side(delta: float) -> void:
	if not _enemy:
		return
	var amplitude: float = 50.0
	var movement_settings: Dictionary = GameManager.get_game_settings_section("movement_settings") if GameManager else {}
	amplitude = float(movement_settings.get("side_to_side_amplitude", amplitude))
	var phase_offset: float = _enemy.formation_index * 0.5
	var side_offset: float = sin(_enemy.time_since_spawn * 2.0 + phase_offset) * amplitude
	var target_pos: Vector2 = _enemy.formation_position + Vector2(side_offset, 0)
	_enemy.position = _enemy.position.lerp(target_pos, 3.0 * delta)

func handle_circle_movement(delta: float) -> void:
	if not _enemy:
		return
	var rotation_speed: float = 2.0 + (_enemy.formation_index % 3) * 0.3
	_circle_angle += delta * rotation_speed
	var circle_offset: Vector2 = Vector2(cos(_circle_angle), sin(_circle_angle)) * _circle_radius
	_enemy.position = _enemy.formation_position + circle_offset

func handle_dive_pattern(delta: float) -> void:
	if not _enemy:
		return
	if is_instance_valid(_enemy.player_reference) and randf() < 0.002:
		var dive_direction: Vector2 = (_enemy.player_reference.global_position - _enemy.global_position).normalized()
		_enemy.position += dive_direction * _enemy.speed * 2.0 * delta
	else:
		_enemy.position = _enemy.position.lerp(_enemy.formation_position, 3.0 * delta)

func handle_swarm_pattern(delta: float) -> void:
	if not _enemy:
		return
	var time_factor: float = _enemy.time_since_spawn * _swarm_coherence
	var primary_wave := Vector2(
		sin(time_factor) * 35.0,
		cos(time_factor * 0.7) * 25.0
	)
	var secondary_wave := Vector2(
		sin(time_factor * 1.5 + _enemy.formation_index * 0.8) * 15.0,
		cos(time_factor * 1.2 + _enemy.formation_index * 0.6) * 10.0
	)
	var swarm_offset: Vector2 = primary_wave + secondary_wave
	var center_attraction: Vector2 = (_swarm_center - _enemy.position) * 0.02
	swarm_offset += center_attraction
	var target_pos: Vector2 = _enemy.formation_position + swarm_offset
	_enemy.position = _enemy.position.lerp(target_pos, 2.5 * delta)
