extends Node

# Global storage for level and difficulty selection
var selected_level_path: String = ""
var selected_difficulty: formation_enums.DifficultyLevel = formation_enums.DifficultyLevel.NORMAL
var enemy_data: Dictionary = {}
var _enemy_data_cache: Dictionary = {}
var _preloaded_level_path: String = ""
var _preloaded_level_scene: PackedScene = null
# Signal for when difficulty selection is complete and ready to load level
@warning_ignore("unused_signal")
signal difficulty_selection_complete

func _ready():
	# Initialize with default values
	selected_level_path = ""
	selected_difficulty = formation_enums.DifficultyLevel.NORMAL
	enemy_data = {}
	_cache_enemy_data_for_difficulties()

func set_selected_level(level_path: String) -> void:
	selected_level_path = level_path
	if GameManager.debug_mode:
		print("LevelSelectionManager: Selected level path set to %s" % level_path)

func set_selected_difficulty(difficulty: formation_enums.DifficultyLevel) -> void:
	selected_difficulty = difficulty
	if GameManager.debug_mode:
		print("LevelSelectionManager: Selected difficulty set to %s" % formation_enums.DifficultyLevel.keys()[difficulty])

func load_enemy_data_for_difficulty() -> bool:
	# Load enemy data based on selected difficulty
	var difficulty_name = formation_enums.DifficultyLevel.keys()[selected_difficulty].to_lower()
	if _enemy_data_cache.has(difficulty_name):
		enemy_data = (_enemy_data_cache[difficulty_name] as Dictionary).duplicate(true)
		print("LevelSelectionManager: Loaded enemy data for %s difficulty (cached)" % difficulty_name)
		return true

	var file_path = _get_enemy_file_path_for_difficulty(difficulty_name)
	var parsed_data = _load_enemy_data_from_file(file_path)
	if parsed_data.is_empty():
		if GameManager.debug_mode:
			print("LevelSelectionManager: Failed to load enemy data for %s difficulty" % difficulty_name)
		return false

	_enemy_data_cache[difficulty_name] = parsed_data.duplicate(true)
	enemy_data = parsed_data.duplicate(true)
	if GameManager.debug_mode:
		print("LevelSelectionManager: Loaded enemy data for %s difficulty" % difficulty_name)
	return true

func request_level_preload(level_path: String) -> void:
	if level_path.is_empty():
		return

	# Skip duplicate requests when the scene is already ready.
	if _preloaded_level_path == level_path and _preloaded_level_scene != null:
		return

	_preloaded_level_path = level_path
	_preloaded_level_scene = null

	var error_code = ResourceLoader.load_threaded_request(level_path, "PackedScene")
	if error_code != OK:
		push_warning("LevelSelectionManager: Failed to start threaded preload for '%s' (error: %d)." % [level_path, error_code])
		_preloaded_level_path = ""
		_preloaded_level_scene = null

func get_preloaded_level(level_path: String) -> PackedScene:
	if level_path.is_empty() or level_path != _preloaded_level_path:
		return null

	if _preloaded_level_scene != null:
		return _preloaded_level_scene

	var status = ResourceLoader.load_threaded_get_status(level_path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var loaded_resource = ResourceLoader.load_threaded_get(level_path)
		if loaded_resource is PackedScene:
			_preloaded_level_scene = loaded_resource as PackedScene
			return _preloaded_level_scene
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		push_warning("LevelSelectionManager: Threaded preload failed for '%s'." % level_path)

	return null

func _cache_enemy_data_for_difficulties() -> void:
	_enemy_data_cache.clear()
	for difficulty_key in formation_enums.DifficultyLevel.keys():
		var difficulty_name = String(difficulty_key).to_lower()
		var file_path = _get_enemy_file_path_for_difficulty(difficulty_name)
		var parsed_data = _load_enemy_data_from_file(file_path)
		if parsed_data.is_empty():
			continue
		_enemy_data_cache[difficulty_name] = parsed_data.duplicate(true)

func _get_enemy_file_path_for_difficulty(difficulty_name: String) -> String:
	var file_path = "res://data/enemy_difficulty_%s.json" % difficulty_name
	if not FileAccess.file_exists(file_path):
		return "res://data/enemy_profiles.json"
	return file_path

func _load_enemy_data_from_file(file_path: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		print("LevelSelectionManager: Failed to open file %s" % file_path)
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		print("LevelSelectionManager: Failed to parse JSON from %s" % file_path)
		return {}

	if json.data is Dictionary:
		var parsed_data: Dictionary = json.data as Dictionary
		return parsed_data.get("data", {}) if parsed_data.has("data") else parsed_data

	return {}

func get_enemy_stats(enemy_type: String) -> Dictionary:
	# Return enemy stats for the specified enemy type
	if enemy_data.has(enemy_type):
		return enemy_data[enemy_type]
	else:
		# Return default values if enemy type not found
		return {
			"score": 100.0,
			"max_health": 100.0,
			"damage_amount": 1.0,
			"speed": 200.0,
			"vertical_speed": 300.0,
			"fire_rate": 1.0
		}

func clear_selection() -> void:
	selected_level_path = ""
	selected_difficulty = formation_enums.DifficultyLevel.NORMAL
	enemy_data = {}
	_preloaded_level_path = ""
	_preloaded_level_scene = null
	if GameManager.debug_mode:
		print("LevelSelectionManager: Selection cleared")
