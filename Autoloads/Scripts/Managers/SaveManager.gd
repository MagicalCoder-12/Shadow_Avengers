extends Node

var gm: Node
var progress_file_path: String = "user://game_progress.dat"
var backup_progress_file_path: String = "user://game_progress_backup.dat"
var autosave_progress: bool = true
var save_debounce_seconds: float = 1.0
const SAVE_FORMAT_MAGIC: String = "shadow_avenger_save"
const SAVE_SCHEMA_VERSION: int = 3

# First satellite the new-player campaign hands out. Enforcing its locked state
# keeps the shop's BUY button on screen until the player buys it.
const FIRST_SATELLITE_ID: String = "Satellite1"
# Campaign checkpoints reached only after the satellite has been purchased and
# equipped. Older saves past these points are left exactly as they are.
const STAGES_AFTER_SATELLITE_EQUIP: Array = [
	"shop_exit", "level1_entry", "level1_playing", "wheel_intro",
	"shadow_map_intro", "shadow_charge_explained", "shadow_activated", "complete",
]

# Default resource values for new or reset progress
const DEFAULT_RESOURCES: Dictionary = {
	"crystal_count": 700,
	"coin_count": 2000,
	"void_shards_count": 200
}
var initial_resources: Dictionary = DEFAULT_RESOURCES.duplicate(true)

# Per-level data storage
var level_scores: Dictionary = {}  # level_num -> score
var level_lives: Dictionary = {}   # level_num -> lives
# Added boss_levels_completed to track which boss levels have been completed
var boss_levels_completed: Array = []  # Array of boss level numbers that have been completed
# Added level_completion_counts to track how many times each level has been completed
var level_completion_counts: Dictionary = {}  # level_num -> completion count

# Added: Difficulty selection unlock tracking
var difficulty_unlocked_showed: bool = false
var hard_difficulty_unlocked_showed: bool = false

# Added: Difficulty tier completion tracking
# Easy tier = levels 1-10, Normal tier = levels 1-20, Hard tier = levels 1-30
var easy_tier_completed: bool = false
var normal_tier_completed: bool = false

# Added: Per-difficulty level completion tracking
# Tracks which levels have been completed in each difficulty
var levels_completed_easy: Array = []
var levels_completed_normal: Array = []
var levels_completed_hard: Array = []

# Tracks the highest difficulty completed for each level (0=none, 1=easy, 2=normal, 3=hard)
var level_highest_difficulty: Dictionary = {}

# Added: Global unlock flags
var normal_globally_unlocked: bool = false
var hard_globally_unlocked: bool = false

# Added: Ad usage tracking variables
var ad_usage_count: int = 0
var ad_last_used_time: int = 0
## New profiles are eligible for automatic tutorials. Any profile created
## before this field existed is migrated as established, so it is never
## interrupted by a tutorial after updating the game.
var tutorial_state: Dictionary = {
	"eligible_for_automatic_tutorials": true,
	"completed": {},
	"state_version": 1
}
var _save_timer: Timer
var _save_pending: bool = false
var _save_in_progress: bool = false

func _ready() -> void:
	gm = GameManager
	_initialize_save_timer()
	# Defer initialization until all autoloads are ready
	call_deferred("initialize")

func initialize() -> void:
	_load_settings_from_config()
	load_progress()

func _load_settings_from_config() -> void:
	if gm:
		progress_file_path = gm.get_game_setting("progress_file_path", "user://game_progress.dat")
		save_debounce_seconds = float(gm.get_game_setting("save_debounce_seconds", 1.0))
		var initial_resources_settings: Dictionary = gm.get_game_settings_section("initial_resources")
		if not initial_resources_settings.is_empty():
			initial_resources["crystal_count"] = int(
				initial_resources_settings.get(
					"crystals",
					initial_resources_settings.get("crystal_count", DEFAULT_RESOURCES["crystal_count"])
				)
			)
			initial_resources["coin_count"] = int(
				initial_resources_settings.get(
					"coins",
					initial_resources_settings.get("coin_count", DEFAULT_RESOURCES["coin_count"])
				)
			)
			initial_resources["void_shards_count"] = int(
				initial_resources_settings.get(
					"void_shards",
					initial_resources_settings.get(
						"void_crystals",
						initial_resources_settings.get("void_shards_count", DEFAULT_RESOURCES["void_shards_count"])
					)
				)
			)
	else:
		push_warning("GameManager not available. Using default file paths.")

func save_progress(force: bool = false) -> void:
	if force:
		_flush_save_now()
		return
	request_save()

func request_save(_reason: String = "") -> void:
	if not autosave_progress:
		return
	_save_pending = true
	if _save_in_progress:
		return
	if save_debounce_seconds <= 0.0:
		_flush_save_now()
		return
	_schedule_save_timer()

func _initialize_save_timer() -> void:
	if _save_timer:
		return
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	add_child(_save_timer)
	_save_timer.timeout.connect(_on_save_timer_timeout)

func _schedule_save_timer() -> void:
	if not _save_timer:
		_initialize_save_timer()
	if _save_timer and _save_timer.is_stopped():
		_save_timer.start(save_debounce_seconds)

func _on_save_timer_timeout() -> void:
	_flush_save_now()

func _flush_save_now() -> void:
	if not autosave_progress:
		return
	if _save_in_progress:
		_save_pending = true
		return
	#Check if managers are ready before saving
	if not gm or not gm.can_persist_progress():
		push_warning("SaveManager: Cannot save progress, managers not ready yet")
		_save_pending = true
		_schedule_save_timer()
		return
	_save_in_progress = true
	_save_pending = false

	var file: FileAccess = FileAccess.open(progress_file_path, FileAccess.WRITE)
	if not file:
		push_error("Failed to save progress: Unable to open file at %s, error: %s" % [progress_file_path, FileAccess.get_open_error()])
		_save_in_progress = false
		return
	
	# Store keyed payload so load order changes do not break compatibility.
	file.store_var(_build_save_payload())
	
	file.close()
	
	# Create backup of the save file
	if FileAccess.file_exists(progress_file_path):
		var dir := DirAccess.open("user://")
		if dir:
			dir.copy(progress_file_path, backup_progress_file_path)
		else:
			push_warning("Failed to access directory for backup")
	else:
		push_error("Save file was not created successfully at %s" % progress_file_path)
	_save_in_progress = false
	if _save_pending:
		_schedule_save_timer()

func load_progress() -> void:
	if _load_progress_from_path(progress_file_path):
		return
	
	# Try backup when primary file is missing/corrupt.
	if _load_progress_from_path(backup_progress_file_path):
		push_warning("Loaded progress from backup file and restoring primary save file.")
		save_progress(true)
		return
	
	reset_progress()

func _build_save_payload() -> Dictionary:
	var payload: Dictionary = {
		"format": SAVE_FORMAT_MAGIC,
		"schema_version": SAVE_SCHEMA_VERSION,
		"game_save_version": int(gm.SAVE_VERSION),
		"progress": {
			"unlocked_levels": gm.get_unlocked_levels_for_save(),
			"shadow_mode_unlocked": gm.get_shadow_mode_unlocked_for_save(),
			"shadow_mode_tutorial_shown": gm.get_shadow_mode_tutorial_shown_for_save(),
			"completed_levels": gm.get_completed_levels_for_save(),
			"level_completion_counts": level_completion_counts.duplicate(true),  # NEW
			"level_scores": level_scores.duplicate(true),
			"level_lives": level_lives.duplicate(true),
			"boss_levels_completed": boss_levels_completed.duplicate(true),
			"difficulty_unlocked_showed": difficulty_unlocked_showed,
			"hard_difficulty_unlocked_showed": hard_difficulty_unlocked_showed,
			"easy_tier_completed": easy_tier_completed,
			"normal_tier_completed": normal_tier_completed,
			"levels_completed_easy": levels_completed_easy.duplicate(true),
			"levels_completed_normal": levels_completed_normal.duplicate(true),
			"levels_completed_hard": levels_completed_hard.duplicate(true),
			"normal_globally_unlocked": normal_globally_unlocked,
			"hard_globally_unlocked": hard_globally_unlocked,
			"level_highest_difficulty": level_highest_difficulty.duplicate(true)
		},
		"player": {
			"lives": 3,
			"selected_ship_id": gm.get_selected_ship_id_for_save(),
			"ships": gm.ships.duplicate(true),
			"satellites": gm.satellites.duplicate(true)
		},
		"resources": {
			"crystals": gm.crystal_count,
			"coins": gm.coin_count,
			"void_shards": gm.void_shards_count
		},
		"wheel": {
			"spins_used_today": gm.wheel_spins_used_today,
			"free_spin_used_today": gm.wheel_free_spin_used_today,
			"ad_spins_used_today": gm.wheel_ad_spins_used_today,
			"last_reset_day": gm.wheel_last_reset_day
		},
		"ads": {
			"usage_count": ad_usage_count,
			"last_used_time": ad_last_used_time
		},
		"tutorials": tutorial_state.duplicate(true)
	}
	return payload

func _load_progress_from_path(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to load progress from %s, error: %s" % [path, FileAccess.get_open_error()])
		return false
	
	if file.get_length() == 0:
		file.close()
		push_warning("Save file is empty: %s" % path)
		return false
	
	var root_value: Variant = file.get_var()
	var loaded_ok: bool = false
	
	if root_value is Dictionary:
		loaded_ok = _load_schema_payload(root_value)
	elif root_value is int:
		loaded_ok = _load_legacy_payload(file, int(root_value))
	else:
		push_warning("Unsupported save payload root type: %s" % typeof(root_value))
	
	file.close()
	return loaded_ok

func _load_schema_payload(payload: Dictionary) -> bool:
	if not gm:
		return false
	
	var format_tag: String = str(payload.get("format", ""))
	if not format_tag.is_empty() and format_tag != SAVE_FORMAT_MAGIC:
		push_warning("Unknown save format: %s" % format_tag)
		return false
	
	var schema_version: int = int(payload.get("schema_version", 0))
	if schema_version <= 0:
		push_warning("Invalid schema version in save payload")
		return false
	
	var progress_data: Dictionary = _dictionary_or_default(payload.get("progress", {}), {})
	var player_data: Dictionary = _dictionary_or_default(payload.get("player", {}), {})
	var resources_data: Dictionary = _dictionary_or_default(payload.get("resources", {}), {})
	var wheel_data: Dictionary = _dictionary_or_default(payload.get("wheel", {}), {})
	var ads_data: Dictionary = _dictionary_or_default(payload.get("ads", {}), {})
	var tutorial_data: Variant = payload.get("tutorials", null)
	
	if gm.has_level_state():
		gm.set_unlocked_levels_from_save(int(progress_data.get("unlocked_levels", 1)))
		gm.set_shadow_mode_unlocked(bool(progress_data.get("shadow_mode_unlocked", false)), "SaveManager._load_schema_payload")
		gm.set_shadow_mode_tutorial_shown(bool(progress_data.get("shadow_mode_tutorial_shown", false)), "SaveManager._load_schema_payload")
		gm.set_completed_levels_from_save(_array_or_default(progress_data.get("completed_levels", []), []))
	
	gm.player_lives = 3
	if gm.has_player_state():
		gm.set_selected_ship_id_from_save(str(player_data.get("selected_ship_id", "Ship1")))
	
	gm.ships = _array_or_default(player_data.get("ships", _get_default_ships()), _get_default_ships())
	gm.satellites = _array_or_default(player_data.get("satellites", _get_default_satellites()), _get_default_satellites())
	gm.crystal_count = max(0, int(resources_data.get("crystals", initial_resources["crystal_count"])))
	gm.coin_count = max(0, int(resources_data.get("coins", initial_resources["coin_count"])))
	gm.void_shards_count = max(0, int(resources_data.get("void_shards", initial_resources["void_shards_count"])))
	if gm.has_method("set_wheel_state_from_save"):
		gm.set_wheel_state_from_save(
			int(wheel_data.get("spins_used_today", 0)),
			int(wheel_data.get("free_spin_used_today", 0)),
			int(wheel_data.get("ad_spins_used_today", 0)),
			int(wheel_data.get("last_reset_day", 0))
		)
	
	level_scores = _dictionary_or_default(progress_data.get("level_scores", {}), {})
	level_lives = _dictionary_or_default(progress_data.get("level_lives", {}), {})
	level_completion_counts = _dictionary_or_default(progress_data.get("level_completion_counts", {}), {})
	boss_levels_completed = _array_or_default(progress_data.get("boss_levels_completed", []), [])
	difficulty_unlocked_showed = bool(progress_data.get("difficulty_unlocked_showed", false))
	hard_difficulty_unlocked_showed = bool(progress_data.get("hard_difficulty_unlocked_showed", false))
	easy_tier_completed = bool(progress_data.get("easy_tier_completed", false))
	normal_tier_completed = bool(progress_data.get("normal_tier_completed", false))
	levels_completed_easy = _array_or_default(progress_data.get("levels_completed_easy", []), [])
	levels_completed_normal = _array_or_default(progress_data.get("levels_completed_normal", []), [])
	levels_completed_hard = _array_or_default(progress_data.get("levels_completed_hard", []), [])
	normal_globally_unlocked = bool(progress_data.get("normal_globally_unlocked", false))
	hard_globally_unlocked = bool(progress_data.get("hard_globally_unlocked", false))
	level_highest_difficulty = _dictionary_or_default(progress_data.get("level_highest_difficulty", {}), {})
	ad_usage_count = max(0, int(ads_data.get("usage_count", 0)))
	ad_last_used_time = max(0, int(ads_data.get("last_used_time", 0)))
	if tutorial_data is Dictionary:
		tutorial_state = _normalize_tutorial_state(tutorial_data)
	else:
		# A save without tutorial metadata predates this feature. Treat it as an
		# established profile and preserve the player's uninterrupted experience.
		tutorial_state = _new_tutorial_state(false)
	
	_normalize_loaded_state()
	return true

func _load_legacy_payload(file: FileAccess, version: int) -> bool:
	if not gm:
		return false
	if version != gm.SAVE_VERSION:
		push_warning("Legacy save file version mismatch. Expected %d, got %d" % [gm.SAVE_VERSION, version])
		return false
	
	var unlocked_levels: Variant = _read_legacy_value(file, 1)
	var shadow_mode_unlocked: Variant = _read_legacy_value(file, false)
	var shadow_mode_tutorial_shown: Variant = _read_legacy_value(file, false)
	var completed_levels: Variant = _read_legacy_value(file, [])
	var selected_ship_id: Variant = _read_legacy_value(file, "Ship1")
	var ships_data: Variant = _read_legacy_value(file, _get_default_ships())
	var satellites_data: Variant = _read_legacy_value(file, _get_default_satellites())
	var crystals: Variant = _read_legacy_value(file, initial_resources["crystal_count"])
	var coins: Variant = _read_legacy_value(file, initial_resources["coin_count"])
	var void_shards: Variant = _read_legacy_value(file, initial_resources["void_shards_count"])
	var loaded_level_scores: Variant = _read_legacy_value(file, {})
	var loaded_level_lives: Variant = _read_legacy_value(file, {})
	var loaded_boss_levels: Variant = _read_legacy_value(file, [])
	var loaded_ad_usage_count: Variant = _read_legacy_value(file, 0)
	var loaded_ad_last_used_time: Variant = _read_legacy_value(file, 0)
	
	if gm.has_level_state():
		gm.set_unlocked_levels_from_save(int(unlocked_levels))
		gm.set_shadow_mode_unlocked(bool(shadow_mode_unlocked), "SaveManager._load_legacy_payload")
		gm.set_shadow_mode_tutorial_shown(bool(shadow_mode_tutorial_shown), "SaveManager._load_legacy_payload")
		gm.set_completed_levels_from_save(completed_levels)
	
	gm.player_lives = 3
	if gm.has_player_state():
		gm.set_selected_ship_id_from_save(str(selected_ship_id))
	
	gm.ships = ships_data
	gm.satellites = satellites_data
	gm.crystal_count = max(0, int(crystals))
	gm.coin_count = max(0, int(coins))
	gm.void_shards_count = max(0, int(void_shards))
	if gm.has_method("set_wheel_state_from_save"):
		gm.set_wheel_state_from_save(0, 0, 0, 0)
	
	level_scores = loaded_level_scores
	level_lives = loaded_level_lives
	level_completion_counts = {}
	boss_levels_completed = loaded_boss_levels
	difficulty_unlocked_showed = false
	hard_difficulty_unlocked_showed = false
	easy_tier_completed = false
	normal_tier_completed = false
	levels_completed_easy = []
	levels_completed_normal = []
	levels_completed_hard = []
	normal_globally_unlocked = false
	hard_globally_unlocked = false
	level_highest_difficulty = {}
	ad_usage_count = max(0, int(loaded_ad_usage_count))
	ad_last_used_time = max(0, int(loaded_ad_last_used_time))
	# Legacy sequential saves are always pre-tutorial profiles.
	tutorial_state = _new_tutorial_state(false)
	
	_normalize_loaded_state()
	return true

func _read_legacy_value(file: FileAccess, default_value: Variant) -> Variant:
	if file.eof_reached():
		return default_value
	return file.get_var()

func _dictionary_or_default(value: Variant, default_value: Dictionary) -> Dictionary:
	return value if value is Dictionary else default_value

func _array_or_default(value: Variant, default_value: Array) -> Array:
	return value if value is Array else default_value

func _normalize_loaded_state() -> void:
	if gm.ships.is_empty() or not (gm.ships is Array):
		gm.ships = _get_default_ships()
		push_warning("Loaded ships data was invalid. Using default data.")
	
	if gm.satellites.is_empty() or not (gm.satellites is Array):
		gm.satellites = _get_default_satellites()
		push_warning("Loaded satellites data was invalid. Using default data.")
	
	if not (level_scores is Dictionary):
		level_scores = {}
	if not (level_lives is Dictionary):
		level_lives = {}
	if not (level_completion_counts is Dictionary):
		level_completion_counts = {}
	if not (boss_levels_completed is Array):
		boss_levels_completed = []
	
	_apply_data_validation()

# Helper function to apply validation to loaded data
func _apply_data_validation() -> void:
	# Validate ships data
	for ship in gm.ships:
		if not ship.has("unlocked"):
			ship["unlocked"] = false
		if not ship.has("ascend_count"):
			ship["ascend_count"] = 0
		if not ship.has("can_ascend"):
			ship["can_ascend"] = false
		if ship.has("textures"):
			for key in ship["textures"]:
				var path = ship["textures"][key]
				if not ResourceLoader.exists(path, "Texture2D"):
					push_warning("Invalid texture path %s for ship %s, using fallback" % [path, ship.get("display_name", "Unknown")])
					ship["textures"][key] = "res://Assets/player/ship_textures/ship_01_lvl0.png"
	
	# Validate satellites data
	for satellite in gm.satellites:
		if not satellite.has("base_damage"):
			# Legacy migration: old saves stored full attack in damage_bonus.
			satellite["base_damage"] = max(1, int(satellite.get("damage_bonus", 5)))
			satellite["damage_bonus"] = 0
		if not satellite.has("damage_bonus"):
			satellite["damage_bonus"] = 0
		satellite["base_damage"] = max(1, int(satellite.get("base_damage", 5)))
		satellite["damage_bonus"] = max(0, int(satellite.get("damage_bonus", 0)))
		if not satellite.has("unlocked"):
			satellite["unlocked"] = false
		if not satellite.has("ascend_count"):
			satellite["ascend_count"] = 0
		if not satellite.has("can_ascend"):
			satellite["can_ascend"] = false
		if satellite.has("texture"):
			var path = satellite["texture"]
			if not ResourceLoader.exists(path, "Texture2D"):
				push_warning("Invalid satellite texture path %s for %s, using fallback" % [path, satellite.get("display_name", "Unknown")])
				satellite["texture"] = "res://Assets/Satellite/Sat_textures/Sat1.png"

	_migrate_tutorial_satellite_lock()


## Saves written before the shop-tutorial rework kept the first satellite
## unlocked. That hides the shop's BUY button (the satellite reads as owned, so
## only Equip + arrows appear) and dead-ends the new-player campaign. Until the
## checkpoint shows the satellite was already bought, force it locked so the flow
## reads Buy -> Equip. Established and completed campaigns are never touched.
func _migrate_tutorial_satellite_lock() -> void:
	if not bool(tutorial_state.get("eligible_for_automatic_tutorials", false)):
		return
	if get_tutorial_campaign_stage() in STAGES_AFTER_SATELLITE_EQUIP:
		return
	for satellite in gm.satellites:
		if not (satellite is Dictionary):
			continue
		if str(satellite.get("id", "")) != FIRST_SATELLITE_ID:
			continue
		if bool(satellite.get("unlocked", false)):
			satellite["unlocked"] = false
			push_warning("Tutorial migration: locked %s so the shop keeps offering BUY." % FIRST_SATELLITE_ID)


func reset_progress() -> void:
	gm.player_lives = 3
	gm.reset_player_stats()
	gm.reset_level_progress()
	gm.ships = _get_default_ships()
	gm.satellites = _get_default_satellites()
	gm.crystal_count = initial_resources["crystal_count"]
	gm.coin_count = initial_resources["coin_count"]
	gm.void_shards_count = initial_resources["void_shards_count"]
	level_scores = {}
	level_lives = {}
	# Reset level_completion_counts data
	level_completion_counts = {}
	# Reset boss_levels_completed data
	boss_levels_completed = []
	# Reset difficulty_unlocked_showed data
	difficulty_unlocked_showed = false
	hard_difficulty_unlocked_showed = false
	easy_tier_completed = false
	normal_tier_completed = false
	levels_completed_easy = []
	levels_completed_normal = []
	levels_completed_hard = []
	level_highest_difficulty = {}
	normal_globally_unlocked = false
	hard_globally_unlocked = false
	ad_usage_count = 0
	ad_last_used_time = 0
	# Reset creates a new profile, which should receive the current onboarding.
	tutorial_state = _new_tutorial_state(true)
	if gm and gm.has_method("reset_wheel_state"):
		gm.reset_wheel_state(true)
	if autosave_progress:
		save_progress(true)

func _exit_tree() -> void:
	if _save_timer and _save_timer.is_inside_tree():
		_save_timer.stop()
	save_progress(true)

# Add functions for level completion count tracking
func get_level_completion_count(level_num: int) -> int:
	return level_completion_counts.get(level_num, 0)

func increment_level_completion_count(level_num: int) -> void:
	var current_count = get_level_completion_count(level_num)
	level_completion_counts[level_num] = current_count + 1
	if autosave_progress:
		save_progress()


func should_show_tutorial(tutorial_id: String) -> bool:
	if tutorial_id.is_empty():
		return false
	if not bool(tutorial_state.get("eligible_for_automatic_tutorials", false)):
		return false
	return not is_tutorial_completed(tutorial_id)


func is_tutorial_completed(tutorial_id: String) -> bool:
	var completed: Variant = tutorial_state.get("completed", {})
	return completed is Dictionary and bool(completed.get(tutorial_id, false))


func mark_tutorial_completed(tutorial_id: String) -> void:
	if tutorial_id.is_empty():
		return
	var completed: Dictionary = _dictionary_or_default(tutorial_state.get("completed", {}), {})
	completed[tutorial_id] = true
	tutorial_state["completed"] = completed
	if autosave_progress:
		save_progress()


func _new_tutorial_state(is_new_profile: bool) -> Dictionary:
	return {
		"eligible_for_automatic_tutorials": is_new_profile,
		"completed": {},
		"campaign_stage": "level0_intro" if is_new_profile else "complete",
		"flags": {},
		"state_version": 2
	}


func _normalize_tutorial_state(value: Dictionary) -> Dictionary:
	var state := _new_tutorial_state(bool(value.get("eligible_for_automatic_tutorials", false)))
	state["completed"] = _dictionary_or_default(value.get("completed", {}), {})
	state["campaign_stage"] = str(value.get("campaign_stage", state["campaign_stage"]))
	state["flags"] = _dictionary_or_default(value.get("flags", {}), {})
	state["state_version"] = max(2, int(value.get("state_version", 1)))
	return state


func get_tutorial_campaign_stage() -> String:
	return str(tutorial_state.get("campaign_stage", "complete"))


func set_tutorial_campaign_stage(stage: String) -> void:
	if stage.is_empty():
		return
	tutorial_state["campaign_stage"] = stage
	if autosave_progress:
		save_progress()


func get_tutorial_flag(flag: String) -> bool:
	var flags: Variant = tutorial_state.get("flags", {})
	return flags is Dictionary and bool(flags.get(flag, false))


func set_tutorial_flag(flag: String, value: bool = true) -> void:
	if flag.is_empty():
		return
	var flags: Dictionary = _dictionary_or_default(tutorial_state.get("flags", {}), {})
	flags[flag] = value
	tutorial_state["flags"] = flags
	if autosave_progress:
		save_progress()

func _get_default_ships() -> Array:
	var ships = gm.get_config_ships_data() if gm else []
	if not ships.is_empty():
		return ships
	return [{
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
		"unlocked": false,
		"description": "A mysterious vessel that harnesses both shadow and light",
		"textures": {
			"base": "res://Assets/player/ship_textures/ship_01_lvl0.png",
			"upgrade_1": "res://Assets/player/ship_textures/ship_01_lvl1.png",
			"upgrade_2": "res://Assets/player/ship_textures/ship_01_lvl2.png"
		}
	}]

func _get_default_satellites() -> Array:
	var satellites = gm.get_config_satellites_data() if gm else []
	if not satellites.is_empty():
		return satellites
	return [{
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
		"description": "A basic but reliable orbital companion",
		"texture": "res://Assets/player/Sat_textures/Sat1.png",
		"purchase_cost": 0
	}]

# Functions for difficulty-specific level completion tracking
# Mark a level as completed in a specific difficulty
# Also tracks highest difficulty completed for that level
func mark_level_completed_in_difficulty(level_num: int, difficulty: String) -> void:
	
	var difficulty_value = 0
	match difficulty:
		"Easy", "EASY":
			difficulty_value = 1
			if not levels_completed_easy.has(level_num):
				levels_completed_easy.append(level_num)
				# Check if Level 10 Easy is completed to unlock Normal globally
				if level_num == 10:
					normal_globally_unlocked = true
					if gm.debug_mode:
						print("SaveManager: NORMAL GLOBALLY UNLOCKED (Level 10 Easy completed)")
				if gm.debug_mode:
					print("SaveManager: Level %d marked as completed in Easy" % level_num)
		"Normal", "NORMAL":
			difficulty_value = 2
			if not levels_completed_normal.has(level_num):
				levels_completed_normal.append(level_num)
				# Check if Level 20 Normal is completed to unlock Hard globally
				if level_num == 20:
					hard_globally_unlocked = true
					if gm.debug_mode:
						print("SaveManager: HARD GLOBALLY UNLOCKED (Level 20 Normal completed)")
				if gm.debug_mode:
					print("SaveManager: Level %d marked as completed in Normal" % level_num)
		"Hard", "HARD":
			difficulty_value = 3
			if not levels_completed_hard.has(level_num):
				levels_completed_hard.append(level_num)
				if gm.debug_mode:
					print("SaveManager: Level %d marked as completed in Hard" % level_num)
		_:
			if gm.debug_mode:
				print("SaveManager: WARNING - Unknown difficulty '%s'" % difficulty)
	
	# Update highest difficulty if this is higher than previous
	var current_highest = level_highest_difficulty.get(level_num, 0)
	if difficulty_value > current_highest:
		level_highest_difficulty[level_num] = difficulty_value
		if gm.debug_mode:
			print("SaveManager: Level %d highest difficulty updated to %s (was %d)" % [level_num, difficulty, current_highest])
	
	if autosave_progress:
		save_progress()

# Get the star level for a level (0=none, 1=Bronze, 2=Silver, 3=Gold)
func get_level_star(level_num: int) -> int:
	return level_highest_difficulty.get(level_num, 0)

# Debug function to check all tracked completions
func debug_print_completions() -> void:
	# Early return (instead of gating each print) so the "%s" % array formatting
	# below is never evaluated in a release build - it would raise a formatting
	# error there even with the output suppressed.
	if not DebugFlags.enabled:
		return
	print("=== SaveManager Debug ===")
	print("levels_completed_easy: %s" % [levels_completed_easy])
	print("levels_completed_normal: %s" % [levels_completed_normal])
	print("levels_completed_hard: %s" % [levels_completed_hard])
	print("level_highest_difficulty: %s" % [level_highest_difficulty])
	print("normal_globally_unlocked: %s" % [normal_globally_unlocked])
	print("hard_globally_unlocked: %s" % [hard_globally_unlocked])
	print("=========================")

# Check if a level is completed in a specific difficulty
func is_level_completed_in_difficulty(level_num: int, difficulty: String) -> bool:
	match difficulty:
		"Easy", "EASY":
			return levels_completed_easy.has(level_num)
		"Normal", "NORMAL":
			return levels_completed_normal.has(level_num)
		"Hard", "HARD":
			return levels_completed_hard.has(level_num)
	return false

# Check if Normal difficulty is globally unlocked
func is_normal_globally_unlocked() -> bool:
	return normal_globally_unlocked

# Check if Hard difficulty is globally unlocked
func is_hard_globally_unlocked() -> bool:
	return hard_globally_unlocked
