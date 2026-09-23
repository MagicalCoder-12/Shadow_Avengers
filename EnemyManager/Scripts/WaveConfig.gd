# WaveConfig
# Resource class for defining enemy wave configurations in levels
# 
# Usage:
# 1. Create a new resource from this script
# 2. Set the desired properties in the inspector
# 3. Assign to a level's waves array
#
# For boss waves:
# - Set the boss_scene property to a boss scene
# - Leave enemy_type as default (ignored for boss waves)
#
# For regular enemy waves:
# - Set enemy_type to desired enemy
# - Configure formation and entry pattern
# - Set difficulty and density

extends Resource
class_name WaveConfig

# Import formation_enums to access shared enums
const FormationEnums = preload("res://EnemyManager/Scripts/formation_enums.gd")

# Import shared enums (from your shared enum script, e.g., formation_enums.gd)
@export var formation_type: FormationEnums.FormationType = FormationEnums.FormationType.CIRCLE:
	set(value):
		formation_type = value
		_update_count_options()

@export var entry_pattern: FormationEnums.EntryPattern = FormationEnums.EntryPattern.SIDE_CURVE

# CORRECTED: Difficulty enum now matches the Enemy script
@export var difficulty: FormationEnums.DifficultyLevel = FormationEnums.DifficultyLevel.EASY

const ENEMY_TYPE_TO_KEY: Dictionary = {
	FormationEnums.EnemyType.MOB1: "mob1",
	FormationEnums.EnemyType.MOB2: "mob2",
	FormationEnums.EnemyType.MOB3: "mob3",
	FormationEnums.EnemyType.SLOW_SHOOTER: "SlowShooter",	
	FormationEnums.EnemyType.FAST_ENEMY: "FastEnemy",
	FormationEnums.EnemyType.BOUNCER_ENEMY: "BouncerEnemy",
	FormationEnums.EnemyType.BOMBER_BUG: "BomberBug",
	FormationEnums.EnemyType.OBLIVION_TANK: "OblivionTank",
	FormationEnums.EnemyType.PHASE_PHANTOM: "PhasePhantom",
	FormationEnums.EnemyType.SHADOW_SENTINEL: "ShadowSentinel",
	FormationEnums.EnemyType.ELITE_ENEMY: "EliteEnemy"
}

const ENEMY_KEY_TO_TYPE: Dictionary = {
	"mob1": FormationEnums.EnemyType.MOB1,
	"mob2": FormationEnums.EnemyType.MOB2,
	"mob3": FormationEnums.EnemyType.MOB3,
	"SlowShooter": FormationEnums.EnemyType.SLOW_SHOOTER,
	"FastEnemy": FormationEnums.EnemyType.FAST_ENEMY,
	"BouncerEnemy": FormationEnums.EnemyType.BOUNCER_ENEMY,
	"BomberBug": FormationEnums.EnemyType.BOMBER_BUG,
	"OblivionTank": FormationEnums.EnemyType.OBLIVION_TANK,
	"PhasePhantom": FormationEnums.EnemyType.PHASE_PHANTOM,
	"ShadowSentinel": FormationEnums.EnemyType.SHADOW_SENTINEL,
	"EliteEnemy": FormationEnums.EnemyType.ELITE_ENEMY
}

var _enemy_type: FormationEnums.EnemyType = FormationEnums.EnemyType.MOB1
@export var enemy_type: FormationEnums.EnemyType = FormationEnums.EnemyType.MOB1:
	get:
		return _enemy_type
	set(value):
		_enemy_type = _coerce_enemy_type(value)

# NEW: Dedicated boss scene for boss waves
# When set, this creates a boss wave with a single boss enemy
@export var boss_scene: PackedScene

# Dynamic enemy count based on formation type
@export_enum("Sparse", "Normal", "Dense", "Maximum")
var enemy_density: String = "Sparse"

# Formation parameters
@export var formation_center: Vector2 = Vector2(640, 600)
@export var formation_radius: float = 300.0
@export var formation_spacing: float = 100.0
@export var spawn_delay: float = 0.3
@export var entry_speed: float = 500.0

# Internal properties used by FormationManager (don't export these)
var spawn_pos: Vector2
var entry_pos: Vector2
var center: Vector2
var count: int
var padding: float

# Optimal enemy counts for each formation type
var formation_counts := {
	FormationEnums.FormationType.CIRCLE: [6, 8, 12, 16],          # Even divisions for circle
	FormationEnums.FormationType.SPIRAL: [8, 12, 16, 20],         # Good for spiral progression
	FormationEnums.FormationType.DIAMOND: [6, 8, 12, 16],         # Symmetric diamond shapes
	FormationEnums.FormationType.GRID: [9, 16, 25, 36],           # Perfect squares (3x3, 4x4, 5x5, 6x6)
	FormationEnums.FormationType.V_FORMATION: [6, 8, 10, 12],     # Even numbers for balanced V
	FormationEnums.FormationType.DOUBLE_CIRCLE: [8, 12, 16, 20],  # Even for inner/outer circles
	FormationEnums.FormationType.HEXAGON: [6, 12, 18, 24],        # Multiples of 6 for hexagon sides
	FormationEnums.FormationType.TRIANGLE: [6, 10, 15, 21],       # Triangular numbers (3+2+1, 4+3+2+1, etc.),
	FormationEnums.FormationType.V_WAVE: [8, 12, 16, 20],         # New V-wave formation
	FormationEnums.FormationType.CLUSTER: [6, 9, 12, 15],         # New cluster formation
	FormationEnums.FormationType.DYNAMIC: [8, 12, 16, 20]        # New dynamic formation
}

const BASE_ENEMY_SCENE_PATH: String = "res://Enemy/Enemy.tscn"
const ENEMY_TYPE_SCENE_PATHS: Dictionary = {
	"mob1": "res://Enemy/mob_1.tscn",
	"mob2": "res://Enemy/mob_2.tscn",
	"mob3": "res://Enemy/mob_3.tscn",
	"SlowShooter": "res://Enemy/minion.tscn",
	"FastEnemy": "res://Enemy/fast_enemy.tscn",
	"BouncerEnemy": "res://Enemy/bouncer_enemy.tscn",
	"BomberBug": "res://Enemy/bomber.tscn",
	"OblivionTank": "res://Enemy/minion.tscn",
	"PhasePhantom": "res://Enemy/phase_phantom_enemy.tscn",
	"ShadowSentinel": "res://Enemy/minion.tscn",
	"EliteEnemy": "res://Enemy/minion.tscn"
}
var _cached_base_enemy_scene: PackedScene
var _cached_enemy_type_scenes: Dictionary = {}

# Returns the configured enemy or boss scene
func get_enemy_scene() -> PackedScene:
	if boss_scene:
		return boss_scene
	var enemy_key: String = get_enemy_type_key()
	var enemy_scene: PackedScene = _resolve_enemy_scene_for_type(enemy_key)
	if enemy_scene:
		return enemy_scene
	if not ENEMY_KEY_TO_TYPE.has(enemy_key):
		push_warning("Invalid enemy_type '%s' in WaveConfig. Using base enemy scene." % enemy_key)
	return _resolve_base_enemy_scene()

func _resolve_enemy_scene_for_type(enemy_key: String) -> PackedScene:
	if not ENEMY_TYPE_SCENE_PATHS.has(enemy_key):
		return null

	if _cached_enemy_type_scenes.has(enemy_key):
		var cached_scene: Variant = _cached_enemy_type_scenes[enemy_key]
		if cached_scene is PackedScene and (cached_scene as PackedScene).can_instantiate():
			return cached_scene as PackedScene

	var scene_path: String = str(ENEMY_TYPE_SCENE_PATHS[enemy_key])
	if not ResourceLoader.exists(scene_path):
		push_warning("WaveConfig: Scene for enemy type '%s' not found at '%s'. Using base enemy scene." % [enemy_key, scene_path])
		return null

	var loaded_scene: Resource = load(scene_path)
	if loaded_scene is PackedScene:
		_cached_enemy_type_scenes[enemy_key] = loaded_scene
		return loaded_scene as PackedScene

	push_warning("WaveConfig: Failed loading scene '%s' for enemy type '%s'. Using base enemy scene." % [scene_path, enemy_key])
	return null

func _resolve_base_enemy_scene() -> PackedScene:
	if _cached_base_enemy_scene and _cached_base_enemy_scene.can_instantiate():
		return _cached_base_enemy_scene

	if not ResourceLoader.exists(BASE_ENEMY_SCENE_PATH):
		push_error("WaveConfig: Base enemy scene missing at '%s'" % BASE_ENEMY_SCENE_PATH)
		return null

	var loaded_scene: Resource = load(BASE_ENEMY_SCENE_PATH)
	if loaded_scene is PackedScene:
		_cached_base_enemy_scene = loaded_scene as PackedScene
		return _cached_base_enemy_scene

	push_error("WaveConfig: Failed to load PackedScene from '%s'" % BASE_ENEMY_SCENE_PATH)
	return null

# Get enemy count based on formation type and density
func get_enemy_count() -> int:
	# For boss waves, return 1 if boss_scene is set
	if boss_scene:
		return 1
	var counts = formation_counts.get(formation_type, [6, 8, 12, 16])
	
	match enemy_density:
		"Sparse":
			return counts[0]
		"Normal":
			return counts[1]
		"Dense":
			return counts[2]
		"Maximum":
			return counts[3]
		_:
			return counts[1]  # Default to Normal

# Helper function to update count options when formation type changes
func _update_count_options():
	# This is called when formation_type changes
	# The counts will be automatically updated when get_enemy_count() is called
	pass

# Getter methods that FormationManager expects
func get_formation_type() -> FormationEnums.FormationType:
	return formation_type

func get_entry_pattern() -> FormationEnums.EntryPattern:
	return entry_pattern

func get_formation_center() -> Vector2:
	return formation_center

func get_formation_radius() -> float:
	return formation_radius

func get_formation_spacing() -> float:
	return formation_spacing

func get_spawn_delay() -> float:
	return spawn_delay

func get_entry_speed() -> float:
	return entry_speed

func get_enemy_type_key() -> String:
	return str(ENEMY_TYPE_TO_KEY.get(enemy_type, "mob1"))

func set_enemy_type_from_key(enemy_key: String) -> void:
	enemy_type = _coerce_enemy_type(enemy_key)

# Per-slot enemy type override for mixed formations. When populated with one
# FormationEnums.EnemyType entry per spawned enemy, each formation slot spawns
# and fights as its own type (e.g. mostly FastEnemy non-shooters with a single
# SlowShooter mixed in); empty keeps the whole wave on `enemy_type`.
@export var slot_enemy_types: PackedInt32Array = PackedInt32Array()

func get_slot_enemy_type(index: int) -> FormationEnums.EnemyType:
	if index < slot_enemy_types.size() and ENEMY_TYPE_TO_KEY.has(slot_enemy_types[index]):
		return slot_enemy_types[index] as FormationEnums.EnemyType
	return enemy_type

func get_slot_enemy_type_key(index: int) -> String:
	return str(ENEMY_TYPE_TO_KEY.get(get_slot_enemy_type(index), "mob1"))

func get_slot_enemy_scene(index: int) -> PackedScene:
	if boss_scene:
		return boss_scene
	var enemy_key: String = get_slot_enemy_type_key(index)
	var enemy_scene: PackedScene = _resolve_enemy_scene_for_type(enemy_key)
	if enemy_scene:
		return enemy_scene
	if not ENEMY_KEY_TO_TYPE.has(enemy_key):
		push_warning("Invalid slot enemy_type '%s' in WaveConfig. Using base enemy scene." % enemy_key)
	return _resolve_base_enemy_scene()

func get_enemy_type_display_name() -> String:
	var key: String = get_enemy_type_key()
	return key if not key.is_empty() else "mob1"

func _coerce_enemy_type(value) -> FormationEnums.EnemyType:
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
		var enemy_key := str(value)
		if ENEMY_KEY_TO_TYPE.has(enemy_key):
			return ENEMY_KEY_TO_TYPE[enemy_key] as FormationEnums.EnemyType
		return FormationEnums.EnemyType.MOB1

	if typeof(value) == TYPE_INT:
		var enemy_type_value := int(value)
		if ENEMY_TYPE_TO_KEY.has(enemy_type_value):
			return enemy_type_value as FormationEnums.EnemyType

	return FormationEnums.EnemyType.MOB1

# Debug helper to show what counts are available for current formation
func get_available_counts() -> Array:
	return formation_counts.get(formation_type, [6, 8, 12, 16])

# Get description of current density setting
func get_density_description() -> String:
	var counts = get_available_counts()
	var _current_count = get_enemy_count()
	
	if boss_scene:
		return "Boss (1 enemy)"
	
	match enemy_density:
		"Sparse":
			return "Sparse (%d enemies)" % counts[0]
		"Normal":
			return "Normal (%d enemies)" % counts[1]
		"Dense":
			return "Dense (%d enemies)" % counts[2]
		"Maximum":
			return "Maximum (%d enemies)" % counts[3]
		_:
			return "Normal (%d enemies)" % counts[1]

# NEW: Check if this is a boss wave
func is_boss_wave() -> bool:
	return boss_scene != null

# Debug string representation
func as_debug_string() -> String:
	if boss_scene:
		return "Boss Wave (%s)" % boss_scene.resource_path.get_file()
	else:
		return "%s (%s, %s)" % [get_enemy_type_display_name(), FormationEnums.FormationType.keys()[formation_type], enemy_density]
