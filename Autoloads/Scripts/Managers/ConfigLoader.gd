extends Node

# Configuration data
var game_settings: Dictionary = {}
var ships_data: Array = []
var satellites_data: Array = []
var upgrade_settings: Dictionary = {}
var hud_settings: Dictionary = {}
var level_waves: Dictionary = {} # Key: level number (int), Value: Array of wave configs
var player_settings: Dictionary = {} # Add this line to declare the player_settings property
var enemy_profiles: Dictionary = {}

# File paths
const GAME_SETTINGS_PATH = "res://data/game_settings.json"
const SHIPS_PATH = "res://data/ships.json"
const SATELLITES_PATH = "res://data/satellites.json"
const UPGRADE_SETTINGS_PATH = "res://data/upgrade_settings.json"
const PLAYER_SETTINGS_PATH = "res://data/player_settings.json"
const HUD_SETTINGS_PATH = "res://data/hud_settings.json"
const ENEMY_PROFILES_PATH = "res://data/enemy_profiles.json"
const LEVEL_WAVES_PATH_TEMPLATE = "res://data/level_%d_waves.json"
const CONFIG_SCHEMA_VERSION: int = 1
const DEFAULT_GAME_SETTINGS_PATH = "res://data/defaults/game_settings.v1.json"
const DEFAULT_SHIPS_PATH = "res://data/defaults/ships.v1.json"
const DEFAULT_SATELLITES_PATH = "res://data/defaults/satellites.v1.json"
const DEFAULT_UPGRADE_SETTINGS_PATH = "res://data/defaults/upgrade_settings.v1.json"
const DEFAULT_PLAYER_SETTINGS_PATH = "res://data/defaults/player_settings.v1.json"
const DEFAULT_HUD_SETTINGS_PATH = "res://data/defaults/hud_settings.v1.json"
const DEFAULT_ENEMY_PROFILES_PATH = "res://data/defaults/enemy_profiles.v1.json"

func _ready() -> void:
	"""
	Loads all JSON configuration files at game startup.
	Provides fallback defaults if files are missing or corrupted.
	"""

	# Load game settings
	var default_game_settings := _get_default_game_settings()
	game_settings = _load_json_file(GAME_SETTINGS_PATH, default_game_settings)
	if not _validate_config(default_game_settings, game_settings, "game_settings"):
		push_error("Failed to validate game settings. Using fallback defaults.")
		game_settings = default_game_settings

	# Load ships data
	var default_ships := _get_default_ships_data()
	ships_data = _load_json_file(SHIPS_PATH, default_ships)
	if not _validate_config(default_ships, ships_data, "ships"):
		push_error("Failed to validate ships data. Using fallback default ships.")
		ships_data = default_ships

	# Load satellites data
	var default_satellites := _get_default_satellites_data()
	satellites_data = _load_json_file(SATELLITES_PATH, default_satellites)
	if not _validate_config(default_satellites, satellites_data, "satellites"):
		push_error("Failed to validate satellites data. Using fallback default satellites.")
		satellites_data = default_satellites
	# Validate satellite textures
	for satellite in satellites_data:
		if satellite.has("texture"):
			var texture_path = satellite["texture"]
			if not ResourceLoader.exists(texture_path, "Texture2D"):
				push_warning("Invalid satellite texture path %s for %s, using fallback" % [texture_path, satellite.get("display_name", "Unknown")])
				satellite["texture"] = "res://Assets/Satellite/Sat_textures/Sat1.png"

	# Load upgrade settings
	var default_upgrade_settings := _get_default_upgrade_settings()
	upgrade_settings = _load_json_file(UPGRADE_SETTINGS_PATH, default_upgrade_settings)
	if not _validate_config(default_upgrade_settings, upgrade_settings, "upgrade_settings"):
		push_error("Failed to validate upgrade settings. Using fallback defaults.")
		upgrade_settings = default_upgrade_settings

	# Load HUD settings
	var default_hud_settings := _get_default_hud_settings()
	hud_settings = _load_json_file(HUD_SETTINGS_PATH, default_hud_settings)
	if not _validate_config(default_hud_settings, hud_settings, "hud_settings"):
		push_error("Failed to validate HUD settings. Using fallback defaults.")
		hud_settings = default_hud_settings

	# Load enemy profiles used by Enemy subclasses/base profile mapping
	var default_enemy_profiles := _get_default_enemy_profiles()
	enemy_profiles = _load_json_file(ENEMY_PROFILES_PATH, default_enemy_profiles)
	if not _validate_config(default_enemy_profiles, enemy_profiles, "enemy_profiles"):
		push_error("Failed to validate enemy profiles. Using fallback defaults.")
		enemy_profiles = default_enemy_profiles
	
	# Load player settings
	var default_player_settings := _get_default_player_settings()
	player_settings = _load_json_file(PLAYER_SETTINGS_PATH, default_player_settings)
	if not _validate_config(default_player_settings, player_settings, "player_settings"):
		push_error("Failed to validate player settings. Using fallback defaults.")
		player_settings = default_player_settings

func _get_default_game_settings() -> Dictionary:
	var data = _load_default_json(DEFAULT_GAME_SETTINGS_PATH, {})
	if data is Dictionary:
		return data
	return {
		"progress_file_path": "user://game_progress.dat",
		"default_bullet_speed": 3000.0,
		"default_bullet_damage": 20,
		"max_attack_level": 4,
		"player_balance": {
			"super_mode_duration": 2.0,
			"shadow_mode_duration": 3.5
		}
	}

func _get_default_ships_data() -> Array:
	var data = _load_default_json(DEFAULT_SHIPS_PATH, [])
	if data is Array and not data.is_empty():
		return data
	return [
		{
			"id": "Ship1",
			"display_name": "NoctiSol",
			"rank": "R",
			"current_evolution_stage": 0,
			"max_evolution_stage": 2,
			"final_rank": "LR",
			"speed": 2000,
			"damage": 20,
			"upgrade_count": 0,
			"ascend_count": 0,
			"can_evolve": true,
			"can_ascend": false,
			"unlocked": true,
			"description": "Fallback ship",
			"textures": {
				"base": "res://Assets/player/ship_textures/ship_01_lvl0.png"
			}
		}
	]

func _get_default_satellites_data() -> Array:
	var data = _load_default_json(DEFAULT_SATELLITES_PATH, [])
	if data is Array and not data.is_empty():
		return data
	return [
		{
			"id": "Satellite1",
			"display_name": "Guardian Drone",
			"rank": "R",
			"max_evolution_stage": 2,
			"final_rank": "LR",
			"base_damage": 5,
			"damage_bonus": 0,
			"upgrade_count": 0,
			"ascend_count": 0,
			"can_ascend": false,
			"unlocked": true,
			"description": "Fallback satellite",
			"texture": "res://Assets/Satellite/Sat_textures/Sat1.png",
			"purchase_cost": 0
		}
	]

func _get_default_upgrade_settings() -> Dictionary:
	var data = _load_default_json(DEFAULT_UPGRADE_SETTINGS_PATH, {})
	if data is Dictionary:
		return data
	return {
		"upgrade_crystal_cost": 50,
		"upgrade_coin_cost": 1000,
		"upgrade_ascend_cost": 100,
		"ad_crystal_reward": 10,
		"ad_ascend_reward": 5,
		"ad_coins_reward": 1000,
		"ascension_thresholds": {},
		"ship_evolution_names": {},
		"satellite_ascension_thresholds": {}
	}

func _get_default_hud_settings() -> Dictionary:
	var data = _load_default_json(DEFAULT_HUD_SETTINGS_PATH, {})
	if data is Dictionary:
		return data
	return {
		"charge_per_enemy": 10.0,
		"max_charge": 100.0
	}

func _get_default_player_settings() -> Dictionary: 
	var data = _load_default_json(DEFAULT_PLAYER_SETTINGS_PATH, {})
	if data is Dictionary:
		return data
	return {
		"max_life": 3,
		"speed": 2000.0,
		"touch_speed": 500.0,
		"smoothness": 0.3,
		"normal_fire_delay": 0.3,
		"boundary_padding": 10.0,
		"shadow_speed_multiplier": 1.2,
		"shadow_fire_delay_multiplier": 0.1,
		"spread_angle_increment": 10.0,
		"spawn_point_offset": 5.0,
		"super_mode_damage_boost": 1.5,
		"super_mode_speed_multiplier": 1.5,
		"super_mode_fire_delay": 0.15,
		"super_mode_bullet_speed": 5000.0,
		"shadow_bullet_count": 20,
		"base_bullet_damage": 20,
		"shadow_texture": "res://Assets/player/g-01.png"
	}

func _get_default_enemy_profiles() -> Dictionary:
	var data = _load_default_json(DEFAULT_ENEMY_PROFILES_PATH, {})
	if data is Dictionary:
		return data
	return {}

func _load_default_json(path: String, fallback: Variant) -> Variant:
	var data = _read_json_file(path)
	if data == null:
		push_error("Default config missing or invalid at %s. Using fallback." % path)
		return fallback
	return data

func _read_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Could not open JSON file at path: %s" % path)
		return null
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error != OK:
		push_error("Error parsing JSON file at %s: %s" % [path, json.get_error_message()])
		return null
	
	return _unwrap_versioned_json(json.get_data(), path)

func _unwrap_versioned_json(data: Variant, path: String) -> Variant:
	if data is Dictionary:
		var version_value: Variant = null
		if data.has("schema_version"):
			version_value = data.get("schema_version")
		elif data.has("version"):
			version_value = data.get("version")
		
		if version_value != null:
			var version_int := int(version_value)
			if version_int != CONFIG_SCHEMA_VERSION:
				push_error("Config schema version mismatch in %s. Expected %d, got %d." % [path, CONFIG_SCHEMA_VERSION, version_int])
				return null
			
			if data.has("items"):
				return data.get("items", [])
			if data.has("data"):
				return data.get("data", {})
			
			# Fixed: Explicitly type the duplicated dictionary
			var payload: Dictionary = data.duplicate()
			payload.erase("schema_version")
			payload.erase("version")
			return payload
		
		return data
	
	return data

func _load_json_file(path: String, default: Variant) -> Variant:
	"""
	Loads and parses a JSON file, returning the parsed data or the default value on failure.
	"""
	var data = _read_json_file(path)
	if data == null:
		return default
	return data

func _validate_config(schema: Variant, data: Variant, context: String) -> bool:
	var ok := _validate_against_schema(schema, data, context)
	if not ok:
		push_error("Schema validation failed for %s. Using defaults." % context)
	return ok

func _validate_against_schema(schema: Variant, data: Variant, context: String) -> bool:
	if schema is Dictionary:
		if not data is Dictionary:
			push_error("Schema mismatch at %s: expected Dictionary." % context)
			return false
		for key in schema.keys():
			if not data.has(key):
				push_error("Schema mismatch at %s: missing key '%s'." % [context, str(key)])
				return false
			if not _validate_against_schema(schema[key], data[key], "%s.%s" % [context, str(key)]):
				return false
		return true
	
	if schema is Array:
		if not data is Array:
			push_error("Schema mismatch at %s: expected Array." % context)
			return false
		if schema.is_empty():
			return true
		var element_schema = schema[0]
		for i in range(data.size()):
			if not _validate_against_schema(element_schema, data[i], "%s[%d]" % [context, i]):
				return false
		return true
	
	return _is_type_compatible(schema, data, context)

func _is_type_compatible(schema_value: Variant, data_value: Variant, context: String) -> bool:
	if _is_number(schema_value) and _is_number(data_value):
		return true
	if typeof(schema_value) == typeof(data_value):
		return true
	push_error("Schema mismatch at %s: expected %s, got %s." % [context, typeof(schema_value), typeof(data_value)])
	return false

func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
