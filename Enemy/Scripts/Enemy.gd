@abstract
class_name Enemy
extends Area2D

# --- Preloaded Resources ---
const ENEMY_MOVEMENT_SERVICE_SCRIPT := preload("res://Enemy/Scripts/Services/EnemyMovementService.gd")
const ENEMY_COMBAT_SERVICE_SCRIPT := preload("res://Enemy/Scripts/Services/EnemyCombatService.gd")
const ENEMY_LIFECYCLE_SERVICE_SCRIPT := preload("res://Enemy/Scripts/Services/EnemyLifecycleService.gd")

# --- Signals ---
@warning_ignore("unused_signal")
signal died
@warning_ignore("unused_signal")
signal enemy_died(payload)
@warning_ignore("unused_signal")
signal formation_reached
@warning_ignore("unused_signal")
signal shadow_state_changed(is_shadow: bool)

# --- Node References ---
@onready var enemy_explosion: AnimatedSprite2D = $Enemy_Explosion
@onready var firing_positions: Node = $FiringPositions
@onready var healthbar: TextureProgressBar = $HealthBar
@onready var explosion_sound: AudioStreamPlayer = $Explosion2
@onready var visible_on_screen_notifier_2d: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var fire_timer: Timer = $FireTimer
@onready var shadow_core_shield: AnimatedSprite2D = $ShadowCoreShield
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# --- Exported Properties ---
@export var score: int = 100
@export var vertical_speed: float = 400.0
@export var max_health: int = 200
@export var damage_amount: int = 1
@export var speed: float = 200.0

@export var shadow_spawn_probability: float = 0.3
@export var shadow_health_multiplier: float = 1.5
@export var shadow_score_multiplier: float = 2.0
@export var shadow_damage_multiplier: float = 1.0
@export var fire_rate: float = 1.0
@export var entry_speed_multiplier: float = 1.0
@export var entry_shadow_shield_time: float = 2.0
@export var shadow_texture: Texture2D
@export_enum(
	"mob1",
	"mob2",
	"mob3",
	"SlowShooter",
	"FastEnemy",
	"BouncerEnemy",
	"BomberBug",
	"OblivionTank",
	"PhasePhantom",
	"ShadowSentinel",
	"EliteEnemy"
) var enemy_type: String = "mob1"

# --- Optimized Attack Pattern System ---
enum AttackPattern { SINGLE_SHOT, SPREAD_SHOT, BURST_SHOT, AIMED_SHOT }

# Pattern weights (configurable per difficulty/mode)
var normal_pattern_weights: Dictionary = {
	AttackPattern.SINGLE_SHOT: 60,    # 60% - most common
	AttackPattern.AIMED_SHOT: 25,     # 25% - aimed at player
	AttackPattern.SPREAD_SHOT: 10,    # 10% - 2 bullet spread
	AttackPattern.BURST_SHOT: 5       # 5% - quick burst
}

var shadow_pattern_weights: Dictionary = {
	AttackPattern.SINGLE_SHOT: 25,    # 25% - less single shots
	AttackPattern.AIMED_SHOT: 35,     # 35% - more aimed shots
	AttackPattern.SPREAD_SHOT: 25,    # 25% - more spread
	AttackPattern.BURST_SHOT: 15      # 15% - more burst
}

# Shooting cooldown management
var can_shoot: bool = true
var shoot_cooldown: float = 0.0
var base_shoot_cooldown: float = 1.5  # Base time between shots
var min_shoot_cooldown: float = 0.8   # Minimum time between shots
var max_shoot_cooldown: float = 2.5   # Maximum time between shots

# --- Shadow Visual Properties ---
var shadow_pulse_speed: float = 2.0
var shadow_alpha_min: float = 0.4
var shadow_alpha_max: float = 0.8

# --- Difficulty System ---
var difficulty_multipliers: Dictionary = {
	formation_enums.DifficultyLevel.EASY: {
		"health": 0.8, "damage": 0.7, "fire_rate": 0.7, "speed": 0.8, "score": 0.8, "shadow_chance": 0.05
	},
	formation_enums.DifficultyLevel.NORMAL: {
		"health": 1.0, "damage": 1.0, "fire_rate": 0.8, "speed": 1.0, "score": 1.0, "shadow_chance": 0.3  # Reduced fire_rate from 1.0 to 0.8
	},
	formation_enums.DifficultyLevel.HARD: {
		"health": 1.5, "damage": 1.3, "fire_rate": 1.0, "speed": 1.2, "score": 1.5, "shadow_chance": 0.5  # Reduced fire_rate from 1.3 to 1.0
	},
	formation_enums.DifficultyLevel.NIGHTMARE: {
		"health": 2.0, "damage": 1.5, "fire_rate": 1.2, "speed": 1.5, "score": 2.0, "shadow_chance": 0.7  # Reduced fire_rate from 1.5 to 1.2
	}
}

# --- Movement Behavior ---
var movement_pattern: int = ENEMY_MOVEMENT_SERVICE_SCRIPT.MOVE_FORMATION_HOLD

# Static cache shared across all Enemy instances to avoid redundant JSON reads.
static var _shared_profiles: Dictionary = {}
static var _shared_profiles_loaded: bool = false

var enemy_type_profiles: Dictionary = {}

# --- Core State Variables ---
var original_speed: float
var original_vertical_speed: float
var health: int = 0
var player_reference: Player = null
var arrived_at_formation: bool = false
var is_alive: bool = true
var spawn_position: Vector2
var formation_position: Vector2
var formation_index: int = 0
var wave_config: WaveConfig = null
var entry_path: Array[Vector2] = []
var entry_path_index: int = 0
var is_in_entry_phase: bool = true
var is_shadow_enemy: bool = false
var is_shadow_mode_active: bool = false
var shadow_mode_unlocked: bool = false
var shadow_tween: Tween
var original_modulate: Color
var original_texture: Texture2D

# --- Movement Variables ---
var current_difficulty: formation_enums.DifficultyLevel = formation_enums.DifficultyLevel.NORMAL
var viewport_size: Vector2
var time_since_spawn: float = 0.0
var shield_damage_reduction: float = 0.7

var movement_service: EnemyMovementService = ENEMY_MOVEMENT_SERVICE_SCRIPT.new()
var combat_service: EnemyCombatService = ENEMY_COMBAT_SERVICE_SCRIPT.new()
var lifecycle_service: EnemyLifecycleService = ENEMY_LIFECYCLE_SERVICE_SCRIPT.new()

# --- Initialization ---
func _ready():
	viewport_size = get_viewport().get_visible_rect().size
	original_speed = speed
	original_vertical_speed = vertical_speed
	original_modulate = modulate
	if sprite:
		original_texture = sprite.texture
	
	# Ensure enemy scale is not smaller than 1.0
	if sprite and sprite.scale.x < 1.0:
		sprite.scale = Vector2(1.0, 1.0)
	
	tree_exiting.connect(_on_tree_exiting)
	movement_service.configure(self)
	combat_service.configure(self)
	lifecycle_service.configure(self)

	_ensure_enemy_profiles_loaded()
	
	health = max_health
	if healthbar:
		healthbar.max_value = max_health
		healthbar.value = health
	
	_setup_fire_timer()
	_connect_signals()
	_update_player_reference()
	_initialize_shadow_state()
	
	if shadow_core_shield:
		shadow_core_shield.visible = true
		shadow_core_shield.play("default")
	
	# Initialize new movement pattern variables
	_init_movement_patterns()
	
	if GameManager.debug_mode:
		print("Enemy spawned: ", enemy_type)

func _load_enemy_type_profiles() -> void:
	# Use the shared static cache if already loaded.
	if _shared_profiles_loaded and not _shared_profiles.is_empty():
		enemy_type_profiles = _shared_profiles
		return

	var profiles: Dictionary = {}
	if ConfigLoader and ConfigLoader.enemy_profiles is Dictionary:
		var config_profiles: Dictionary = ConfigLoader.enemy_profiles as Dictionary
		if not config_profiles.is_empty():
			profiles = config_profiles.duplicate(true)

	if profiles.is_empty():
		profiles = _load_enemy_profiles_from_path("res://data/enemy_profiles.json")
	if profiles.is_empty():
		profiles = _load_enemy_profiles_from_path("res://data/defaults/enemy_profiles.v1.json")

	if profiles.is_empty():
		push_error("Enemy: enemy_profiles is empty. Falling back to exported stat defaults.")

	# Populate the shared cache for all future Enemy instances.
	_shared_profiles = profiles
	_shared_profiles_loaded = true
	enemy_type_profiles = profiles

func _ensure_enemy_profiles_loaded() -> void:
	if not _shared_profiles_loaded or enemy_type_profiles.is_empty():
		_load_enemy_type_profiles()

func _load_enemy_profiles_from_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var json_text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_warning("Enemy: Failed to parse enemy profiles at '%s'." % path)
		return {}

	var parsed: Variant = json.get_data()
	if parsed is Dictionary:
		var parsed_dict: Dictionary = parsed as Dictionary
		if parsed_dict.has("data") and parsed_dict["data"] is Dictionary:
			return (parsed_dict["data"] as Dictionary).duplicate(true)
		return parsed_dict.duplicate(true)

	return {}

func _init_movement_patterns():
	movement_service.init_movement_patterns()

func _load_attack_settings_from_config():
	movement_service.load_attack_settings_from_config()

func _load_movement_settings_from_config():
	movement_service.load_movement_settings_from_config()

func _on_tree_exiting():
	if GameManager.debug_mode:
		print("Enemy: Tree exiting - cleaning up")
	_disconnect_all_signals()
	
	# Kill shadow tween if it exists
	if shadow_tween:
		shadow_tween.kill()
		shadow_tween = null

func _setup_fire_timer():
	combat_service.setup_fire_timer()

func _connect_signals():
	if visible_on_screen_notifier_2d:
		# Only connect screen_entered if not already connected
		if not visible_on_screen_notifier_2d.is_connected("screen_entered", _on_visible_on_screen_notifier_2d_screen_entered):
			visible_on_screen_notifier_2d.screen_entered.connect(_on_visible_on_screen_notifier_2d_screen_entered)
			if GameManager.debug_mode:
				print("Boss: Connected screen_entered signal")
		else:
			if GameManager.debug_mode:
				print("Boss: Skipped connecting screen_entered signal - already connected")
		
		# Only connect screen_exited if not already connected
		if not visible_on_screen_notifier_2d.is_connected("screen_exited", _on_visible_on_screen_notifier_2d_screen_exited):
			visible_on_screen_notifier_2d.screen_exited.connect(_on_visible_on_screen_notifier_2d_screen_exited)
			if GameManager.debug_mode:
				print("Boss: Connected screen_exited signal")
		else:
			if GameManager.debug_mode:
				print("Boss: Skipped connecting screen_exited signal - already connected")
	
func _disconnect_all_signals():
	lifecycle_service.disconnect_all_signals()

func _physics_process(delta: float) -> void:
	if not is_alive or not is_instance_valid(self):
		return
	
	time_since_spawn += delta
	
	_update_player_reference()
	_handle_movement(delta)
	_handle_entry_shield(delta)
	_handle_shooting(delta)
	
	# Keep enemy within screen bounds with buffer
	position.x = clamp(position.x, -50, viewport_size.x + 50)

func _update_player_reference():
	movement_service.update_player_reference()

func _handle_entry_shield(_delta: float):
	movement_service.handle_entry_shield()

func _handle_movement(delta: float):
	movement_service.handle_movement(delta)

func _handle_shooting(delta: float):
	combat_service.handle_shooting(delta)

func _on_fire_timer_timeout():
	combat_service.on_fire_timer_timeout()

# --- Formation Setup ---
@warning_ignore("unused_parameter")
func setup_formation_entry(config: WaveConfig, index: int, formation_pos: Vector2, delay: float = 0.0):
	wave_config = config
	formation_index = index
	formation_position = formation_pos
	
	if not config:
		return

	# assign_formation_slot can be called before _ready(), so load profiles on demand.
	_ensure_enemy_profiles_loaded()
	
	var profile_key: String = config.get_enemy_type_key()
	if not enemy_type_profiles.has(profile_key):
		push_error("Enemy: Missing profile for enemy type '%s'." % profile_key)
		return

	_apply_enemy_profile(profile_key)
	combat_service.reset_enemy_type_state()
	if is_shadow_enemy:
		_apply_shadow_profile_multipliers()
	
	current_difficulty = config.difficulty
	_apply_difficulty_multipliers(current_difficulty)
	
	health = max_health
	if healthbar:
		healthbar.max_value = max_health
		healthbar.value = health
	
	original_speed = speed
	original_vertical_speed = vertical_speed
	_setup_fire_timer()
	
	spawn_position = position
	
	if GameManager.debug_mode:
		print("Enemy formation setup complete")

func _apply_enemy_profile(profile_key: String) -> void:
	if profile_key.is_empty() or not enemy_type_profiles.has(profile_key):
		return

	var profile: Dictionary = enemy_type_profiles.get(profile_key, {}) as Dictionary
	if not _has_required_profile_keys(profile_key, profile):
		return

	enemy_type = profile_key
	score = int(profile["score"])
	max_health = int(profile["max_health"])
	damage_amount = int(profile["damage_amount"])
	speed = float(profile["speed"])
	vertical_speed = float(profile["vertical_speed"])
	fire_rate = maxf(0.01, float(profile["fire_rate"]))
	entry_speed_multiplier = float(profile.get("entry_speed_multiplier", entry_speed_multiplier))
	shadow_spawn_probability = float(profile.get("shadow_spawn_probability", shadow_spawn_probability))

func _has_required_profile_keys(profile_key: String, profile: Dictionary) -> bool:
	var required_keys: PackedStringArray = [
		"score",
		"max_health",
		"damage_amount",
		"speed",
		"vertical_speed",
		"fire_rate"
	]
	for key in required_keys:
		if not profile.has(key):
			push_error("Enemy: Profile '%s' missing required key '%s'." % [profile_key, key])
			return false
	return true

func _apply_shadow_profile_multipliers() -> void:
	max_health = int(max_health * shadow_health_multiplier)
	damage_amount = int(damage_amount * shadow_damage_multiplier)
	score = int(score * shadow_score_multiplier)

func set_entry_path(path: Array[Vector2]):
	entry_path = path
	entry_path_index = 0
	
	if GameManager.debug_mode:
		print("Entry path set with ", path.size(), " waypoints")

func assign_formation_slot(data: Dictionary) -> void:
	if data.has("movement_pattern"):
		_set_movement_pattern(int(data.movement_pattern))
	
	setup_formation_entry(
		data.wave_config,
		data.formation_index,
		data.formation_position,
		data.start_delay
	)
	set_entry_path(data.entry_path)

func _set_movement_pattern(pattern: int) -> void:
	if pattern < ENEMY_MOVEMENT_SERVICE_SCRIPT.MOVE_FORMATION_HOLD or pattern > ENEMY_MOVEMENT_SERVICE_SCRIPT.MOVE_SWARM_PATTERN:
		movement_pattern = ENEMY_MOVEMENT_SERVICE_SCRIPT.MOVE_FORMATION_HOLD
		return
	movement_pattern = pattern

func _apply_difficulty_multipliers(difficulty: formation_enums.DifficultyLevel):
	var multipliers = difficulty_multipliers.get(difficulty, difficulty_multipliers[formation_enums.DifficultyLevel.NORMAL])
	
	max_health = int(max_health * multipliers["health"])
	damage_amount = int(damage_amount * multipliers["damage"])
	fire_rate = fire_rate * multipliers["fire_rate"]
	speed = speed * multipliers["speed"]
	vertical_speed = vertical_speed * multipliers["speed"]
	score = int(score * multipliers["score"])
	
	# Apply shadow probability based on difficulty
	shadow_spawn_probability = multipliers["shadow_chance"]

func _initialize_shadow_state():
	lifecycle_service.initialize_shadow_state()

func _make_shadow_enemy():
	lifecycle_service.make_shadow_enemy()

func _apply_shadow_visuals():
	lifecycle_service.apply_shadow_visuals()

func _start_shadow_pulse():
	lifecycle_service.start_shadow_pulse()

func _on_shadow_pulse_finished():
	lifecycle_service.on_shadow_pulse_finished()

func _set_shadow_alpha(alpha: float):
	lifecycle_service.set_shadow_alpha(alpha)

func _on_shadow_mode_activated():
	lifecycle_service.on_shadow_mode_activated()

func _on_shadow_mode_deactivated():
	lifecycle_service.on_shadow_mode_deactivated()

# --- Damage and Health ---
func damage(amount: int):
	lifecycle_service.apply_damage(amount)

func _show_shield_hit_feedback():
	lifecycle_service.show_shield_hit_feedback()

# --- Death Logic ---
func die():
	lifecycle_service.die()

func _play_death_animation():
	lifecycle_service.play_death_animation()

func _on_death_animation_finished():
	lifecycle_service.on_death_animation_finished()

# --- Screen Management ---
func _on_visible_on_screen_notifier_2d_screen_entered() -> void:
	# Enemy has entered the screen
	pass

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	lifecycle_service.on_visible_screen_exited()

# --- Shadow Mode Updates ---
func on_shadow_mode_changed(active: bool) -> void:
	is_shadow_mode_active = active
	if active:
		_on_shadow_mode_activated()
	else:
		_on_shadow_mode_deactivated()

func on_shadow_mode_unlocked_changed(unlocked: bool) -> void:
	shadow_mode_unlocked = unlocked

func _on_area_entered(area: Area2D) -> void:
	lifecycle_service.handle_area_entered(area)
