extends Node2D

# Import formation_enums to access shared enums
const FormationEnums = preload("res://EnemyManager/Scripts/formation_enums.gd")

# Revive state tracking
var is_revive_pending: bool = false
# Per-level revive usage counters used by ad/crystal revive limits.
var ad_revives_used_this_level: int = 0
var crystal_revives_used_this_level: int = 0

# Default revive economy settings (overridable from upgrade settings).
const DEFAULT_MAX_AD_REVIVES_PER_LEVEL: int = 1
const DEFAULT_MAX_CRYSTAL_REVIVES_PER_LEVEL: int = 2
const DEFAULT_CRYSTAL_REVIVE_BASE_COST: int = 10
const DEFAULT_CRYSTAL_REVIVE_COST_INCREMENT: int = 10
const DEFAULT_WHEEL_MAX_SPINS_PER_DAY: int = 10
const DEFAULT_WHEEL_FREE_SPINS_PER_DAY: int = 1
const DEFAULT_WHEEL_AD_SPINS_PER_DAY: int = 5
const DEFAULT_WHEEL_CRYSTAL_SPIN_COST: int = 20
# SIGNALS
@warning_ignore("unused_signal")
signal ad_reward_granted(ad_type: String)
signal currency_updated(currency_type: String, new_amount: int)
signal on_player_life_changed(life: int)
signal score_updated(new_score: int)
@warning_ignore("unused_signal")
signal game_over_triggered()
signal game_paused(paused: bool)
@warning_ignore("unused_signal")
signal scene_change_started()
@warning_ignore("unused_signal")
signal level_unlocked(new_level: int)
@warning_ignore("unused_signal")
signal wave_started(current_wave: int, total_waves: int)
@warning_ignore("unused_signal")
signal all_waves_cleared()
@warning_ignore("unused_signal")
signal level_completed(level_num: int)
@warning_ignore("unused_signal")
signal shadow_mode_activated
signal shadow_mode_deactivated
@warning_ignore("unused_signal")
signal level_star_earned(level_num: int)
@warning_ignore("unused_signal")
signal ad_failed_to_load(ad_type: String, error_code: Variant)
@warning_ignore("unused_signal")
signal revive_completed(success: bool)
@warning_ignore("unused_signal")
signal ship_stats_updated(ship_id: String, new_damage: int)
@warning_ignore("unused_signal")
signal satellite_stats_updated(satellite_id: String, new_damage_bonus: int)
@warning_ignore("unused_signal")
signal enemy_killed(enemy: Node)
@warning_ignore("unused_signal")
signal prepare_map_scene()
@warning_ignore("unused_signal")
signal player_manager_satellites_changed()
signal god_mode_changed(enabled: bool)

# CONSTANTS
const GROUP_DAMAGEABLE: String = "damageable"
const GROUP_BOSS: String = "Boss"
const SUPER_MODE_SPAWN_COUNT: int = 25
const SAVE_VERSION: int = 1
const GAME_ECONOMY_SERVICE_SCRIPT := preload("res://Autoloads/Scripts/Services/GameEconomyService.gd")
const GAME_PROGRESS_SERVICE_SCRIPT := preload("res://Autoloads/Scripts/Services/GameProgressService.gd")
const GAME_CONFIG_SERVICE_SCRIPT := preload("res://Autoloads/Scripts/Services/GameConfigService.gd")
const GAME_REVIVE_SERVICE_SCRIPT := preload("res://Autoloads/Scripts/Services/GameReviveService.gd")
const GAME_SCENE_SERVICE_SCRIPT := preload("res://Autoloads/Scripts/Services/GameSceneService.gd")

# Ascension thresholds for ships (mirroring upgrade_settings.json)
const ASCENSION_THRESHOLDS: Dictionary = {
	"Ship1": [4, 8],
	"Ship2": [4, 8],
	"Ship3": [4, 8],
	"Ship4": [4, 8, 12, 16],
	"Ship5": [4, 8, 12, 16, 20, 24, 28, 32, 36, 40],
	"Ship6": [4, 8, 12, 16, 20, 24, 28, 32],
	"Ship7": [4, 8, 12, 16, 20, 24],
	"Ship8": [4, 8, 12, 16, 20]
}

# Ascension thresholds for satellites (mirroring upgrade_settings.json)
const SATELLITE_ASCENSION_THRESHOLDS: Dictionary = {
	"Satellite1": [3, 6],
	"Satellite2": [3, 6],
	"Satellite3": [3, 6, 9],
	"Satellite4": [3, 6, 9],
	"Satellite5": [3, 6, 9, 12],
	"Satellite6": [3, 6, 9, 12, 15]
}

# Debug/Developer settings
# Debug Mode is the SINGLE toggle for every developer-only feature: verbose
# debug logging, god mode, dev-win, and all editor shortcuts. It is a
# pass-through of the build-type gate (DebugFlags.enabled): a release export
# reports is_debug_build() == false, so Debug Mode - and therefore every cheat
# behind it - cannot be enabled there, no matter what a save file, a serialized
# scene, or runtime code does. Switching it off also instantly deactivates god
# mode. Kept exported so it can still be toggled while developing.
@export var debug_mode: bool = false: set = set_debug_mode
const GOD_MODE_DAMAGE_MULTIPLIER: int = 10
const GOD_MODE_RESOURCE_AMOUNT: int = 99999
var god_mode_enabled: bool = false

# Bullet constants for compatibility
const DEFAULT_BULLET_SPEED: float = 600.0
const DEFAULT_BULLET_DAMAGE: int = 10

# MANAGERS - Now using autoload references
var save_manager: SaveManager
var ad_manager: AdManager
var scene_manager: SceneManager
var player_manager: PlayerManager
var level_manager: LevelManager

# PERSISTENT GAME STATE
var _score: int = 0
var score: int:
	get: return _score
	set(value):
		if value != _score:
			_score = value
			score_updated.emit(_score)


var _player_lives: int = 3
var player_lives: int:
	get: return _player_lives
	set(value):
		_player_lives = max(0, value)
		on_player_life_changed.emit(_player_lives)

var is_paused: bool = false:
	set(value):
		if value != is_paused:
			is_paused = value
			get_tree().paused = value
			game_paused.emit(value)

var game_over: bool = false
var game_ended: bool = false
var game_won: bool = false

# Current difficulty for the upcoming level
var current_difficulty: FormationEnums.DifficultyLevel = FormationEnums.DifficultyLevel.NORMAL

# SHIP AND CURRENCY DATA
var ships: Array = []
var satellites: Array = []
var _crystal_count: int = 0
var crystal_count: int:
	get: return _crystal_count
	set(value):
		_crystal_count = max(0, value)
		currency_updated.emit("crystals", _crystal_count)
var _coin_count: int = 0
var coin_count: int:
	get: return _coin_count
	set(value):
		_coin_count = max(0, value)
		currency_updated.emit("coins", _coin_count)
var _void_shards_count: int = 0
var void_shards_count: int:
	get: return _void_shards_count
	set(value):
		_void_shards_count = max(0, value)
		currency_updated.emit("void_shards", _void_shards_count)

# Daily wheel state
var wheel_spins_used_today: int = 0
var wheel_free_spin_used_today: int = 0
var wheel_ad_spins_used_today: int = 0
var wheel_last_reset_day: int = 0
var wheel_ad_spin_pending: bool = false

# UPGRADE MENU REFERENCE
@export var upgrade_menu_scene: PackedScene

var shadow_mode_timer: Timer = Timer.new()
var shadow_mode_state: ShadowModeState = ShadowModeState.new()
var saved_map_camera_position: Vector2 = Vector2.ZERO
var has_saved_map_camera_position: bool = false

var level_currency_state: LevelCurrencyState = LevelCurrencyState.new()
var economy_service: GameEconomyService = GAME_ECONOMY_SERVICE_SCRIPT.new()
var progress_service: GameProgressService = GAME_PROGRESS_SERVICE_SCRIPT.new()
var config_service: GameConfigService = GAME_CONFIG_SERVICE_SCRIPT.new()
var revive_service: GameReviveService = GAME_REVIVE_SERVICE_SCRIPT.new()
var game_scene_service: GameSceneService = GAME_SCENE_SERVICE_SCRIPT.new()

func _ready() -> void:
	god_mode_enabled = false
	_apply_debug_gates()

	# Reference autoload managers instead of instantiating them
	save_manager = SaveManager
	ad_manager = AdManager
	scene_manager = SceneManager
	player_manager = PlayerManager
	level_manager = LevelManager

	# Wait for autoloads to initialize
	await get_tree().process_frame

	# Initialize other components
	player_manager.initialize()
	scene_manager.initialize()
	ad_manager.initialize()

	add_child(shadow_mode_timer)
	shadow_mode_timer.timeout.connect(_on_shadow_mode_timer_timeout)

	get_tree().node_added.connect(_on_node_added)

	# Connect prepare_map_scene signal
	if prepare_map_scene.is_connected(_on_prepare_map_scene):
		prepare_map_scene.disconnect(_on_prepare_map_scene)
	prepare_map_scene.connect(_on_prepare_map_scene)

# Connect revive_completed signal to resume game after ad
	if not revive_completed.is_connected(_on_revive_completed):
		revive_completed.connect(_on_revive_completed)

	# Serialized debug_mode=true (game_manager.tscn) must mean god mode is
	# active on launch in debug builds; nothing else ever arms it otherwise.
	# The second branch re-applies the resource grant: gate-time arming runs
	# before SaveManager loads, so load_progress would otherwise overwrite the
	# granted resources with on-disk values.
	if debug_mode and not god_mode_enabled:
		set_god_mode_enabled(true, "ready_debug_mode_on")
	elif debug_mode and god_mode_enabled:
		_grant_god_mode_resources()

func _exit_tree() -> void:
	# Clean up the timer to prevent memory leaks
	if shadow_mode_timer and shadow_mode_timer.is_inside_tree():
		if shadow_mode_timer.timeout.is_connected(_on_shadow_mode_timer_timeout):
			shadow_mode_timer.timeout.disconnect(_on_shadow_mode_timer_timeout)
		shadow_mode_timer.stop()
		shadow_mode_timer.queue_free()

	# Disconnect node_added signal
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)

	# Disconnect prepare_map_scene signal
	if prepare_map_scene.is_connected(_on_prepare_map_scene):
		prepare_map_scene.disconnect(_on_prepare_map_scene)

	# Disconnect revive_completed signal
	if revive_completed.is_connected(_on_revive_completed):
		revive_completed.disconnect(_on_revive_completed)

func trigger_game_over() -> void:
	if game_over or (level_manager and level_manager.is_level_just_completed):
		return
	game_over = true
	AudioManager.mute_bus("Bullet", true)
	AudioManager.mute_bus("Explosion", true)
	# Banner ad will be shown by AdManager when appropriate
	# if ad_manager.is_initialized:
	#     ad_manager.show_banner_ad()
	game_over_triggered.emit()

func request_game_over(_source: String = "") -> void:
	game_over = true

func request_game_over_clear(_source: String = "") -> void:
	game_over = false

func request_revive_pending_start(_source: String = "") -> void:
	is_revive_pending = true

func request_revive_pending_clear(_source: String = "") -> void:
	is_revive_pending = false

# Called at run reset/new level start so revive limits do not carry across levels.
func reset_revive_limits_for_level() -> void:
	revive_service.reset_revive_limits_for_level(self)

# Read revive configuration through GameManager so callers use one source of truth.
func get_max_ad_revives_per_level() -> int:
	return revive_service.get_max_ad_revives_per_level(config_service, ConfigLoader, DEFAULT_MAX_AD_REVIVES_PER_LEVEL)

func get_max_crystal_revives_per_level() -> int:
	return revive_service.get_max_crystal_revives_per_level(config_service, ConfigLoader, DEFAULT_MAX_CRYSTAL_REVIVES_PER_LEVEL)

func get_ad_revives_remaining() -> int:
	return revive_service.get_ad_revives_remaining(get_max_ad_revives_per_level(), ad_revives_used_this_level)

func get_crystal_revives_remaining() -> int:
	return revive_service.get_crystal_revives_remaining(get_max_crystal_revives_per_level(), crystal_revives_used_this_level)

func get_crystal_revive_cost() -> int:
	return revive_service.get_crystal_revive_cost(
		config_service,
		ConfigLoader,
		crystal_revives_used_this_level,
		DEFAULT_CRYSTAL_REVIVE_BASE_COST,
		DEFAULT_CRYSTAL_REVIVE_COST_INCREMENT
	)

# Revives are allowed only while game-over is active and no revive is already pending.
func can_use_ad_revive() -> bool:
	return revive_service.can_use_ad_revive(game_over, is_revive_pending, get_ad_revives_remaining())

func can_use_crystal_revive() -> bool:
	return revive_service.can_use_crystal_revive(game_over, is_revive_pending, get_crystal_revives_remaining())

func mark_ad_revive_used() -> void:
	ad_revives_used_this_level = revive_service.mark_ad_revive_used(
		ad_revives_used_this_level,
		get_max_ad_revives_per_level()
	)

# Deduct crystals and lock revive state atomically so UI/gameplay stay in sync.
func try_spend_crystal_revive() -> Dictionary:
	return revive_service.try_spend_crystal_revive(self)

func set_shadow_mode_enabled(value: bool, _source: String = "") -> void:
	shadow_mode_state.shadow_mode_enabled = value

func set_shadow_mode_unlocked(value: bool, _source: String = "") -> void:
	shadow_mode_state.shadow_mode_unlocked = value

func set_shadow_mode_tutorial_shown(value: bool, _source: String = "") -> void:
	shadow_mode_state.shadow_mode_tutorial_shown = value

func request_shadow_mode_activate(duration: float, _source: String = "") -> void:
	if level_manager and (shadow_mode_state.shadow_mode_unlocked or is_god_mode_active()):
		shadow_mode_state.shadow_mode_enabled = true
		shadow_mode_state.shadow_mode_remaining_time = duration
		shadow_mode_activated.emit()
		shadow_mode_timer.start(duration)

func request_shadow_mode_deactivate(_source: String = "") -> void:
	if level_manager and shadow_mode_state.shadow_mode_enabled:
		shadow_mode_state.shadow_mode_enabled = false
		shadow_mode_state.shadow_mode_remaining_time = 0.0
		if shadow_mode_timer:
			shadow_mode_timer.stop()
		shadow_mode_deactivated.emit()

func request_shadow_mode_deactivate_silent(_source: String = "") -> void:
	if level_manager:
		shadow_mode_state.shadow_mode_enabled = false
		shadow_mode_state.shadow_mode_remaining_time = 0.0
		if shadow_mode_timer:
			shadow_mode_timer.stop()

func set_debug_mode(value: bool) -> void:
	# Assignment inside the setter writes the backing field, no recursion.
	# God mode rides this same toggle: flipping Debug Mode on arms it,
	# flipping it off disarms it.
	# During scene instantiation the node is outside the tree and DebugFlags
	# may not be ready yet, so store the serialized value raw and let _ready
	# apply the build gate. Otherwise the serialized debug_mode=true would be
	# ANDed with a not-ready gate and permanently lost at startup.
	if is_inside_tree():
		debug_mode = value and DebugFlags.enabled
		if debug_mode and not god_mode_enabled:
			set_god_mode_enabled(true, "debug_mode_on")
		elif not debug_mode and god_mode_enabled:
			set_god_mode_enabled(false, "debug_mode_off")
	else:
		debug_mode = value


## Debug-only surfaces are hard-off unless this is a debug build.
func _apply_debug_gates() -> void:
	debug_mode = debug_mode and DebugFlags.enabled

func can_use_god_mode() -> bool:
	return debug_mode

func is_god_mode_active() -> bool:
	return debug_mode and god_mode_enabled

func set_god_mode_enabled(enabled: bool, _source: String = "") -> void:
	var next_state := enabled and debug_mode
	if god_mode_enabled == next_state:
		return

	god_mode_enabled = next_state
	if god_mode_enabled:
		_grant_god_mode_resources()
	elif shadow_mode_state.shadow_mode_enabled:
		request_shadow_mode_deactivate("GameManager.set_god_mode_enabled")

	god_mode_changed.emit(god_mode_enabled)

func toggle_god_mode(_source: String = "") -> void:
	set_god_mode_enabled(not god_mode_enabled, _source)

func get_god_mode_damage(value: int) -> int:
	if not is_god_mode_active():
		return max(1, value)
	return max(1, value * GOD_MODE_DAMAGE_MULTIPLIER)

func _grant_god_mode_resources() -> void:
	if not is_god_mode_active():
		return
	crystal_count = GOD_MODE_RESOURCE_AMOUNT
	coin_count = GOD_MODE_RESOURCE_AMOUNT
	void_shards_count = GOD_MODE_RESOURCE_AMOUNT
	save_progress_if_enabled()

func reset_game() -> void:
	score = 0
	player_lives = 3
	is_paused = false
	request_game_over_clear("reset_game")
	request_shadow_mode_deactivate_silent("reset_game")
	reset_revive_limits_for_level()
	game_ended = false
	game_won = false
	coins_collected_this_level = 0
	crystals_collected_this_level = 0

	# Reset all audio state to prevent BGM overlap
	AudioManager.reset_audio_state()

	# Reset state managers
	level_manager.reset_level_state()
	player_manager.reset_player_stats()
	player_manager.set_spawn_position()
	ad_manager.reset_ad_state()

	# Ensure game tree is unpaused
	get_tree().paused = false



# Reset score and lives for each level (per-level progression)
func reset_for_new_level() -> void:
	# Always reset per-run combat state between levels.
	_score = 0
	_player_lives = 3
	is_paused = false
	request_game_over_clear("reset_for_new_level")
	request_shadow_mode_deactivate_silent("reset_for_new_level")
	reset_revive_limits_for_level()
	game_ended = false
	game_won = false

	coins_collected_this_level = 0
	crystals_collected_this_level = 0
	score_updated.emit(_score)
	on_player_life_changed.emit(_player_lives)

	# Reset player stats to default values to ensure special modes don't carry over between levels
	if player_manager:
		player_manager.reset_player_stats()

	get_tree().paused = false

func complete_level(current_level: int) -> void:
	level_manager.complete_level(current_level)

func complete_current_level() -> void:
	level_manager.complete_level(get_current_level())

func _on_shadow_mode_timer_timeout() -> void:
	request_shadow_mode_deactivate("_on_shadow_mode_timer_timeout")

func _on_node_added(node: Node) -> void:
	# Only dispatch to handlers that care about this node type.
	if node is WaveManager or node.is_in_group("Boss"):
		level_manager.handle_node_added(node)
	if node is Control:
		ad_manager.handle_node_added(node)
		scene_manager.handle_node_added(node)

func connect_score_signals(target_node: Node) -> void:
	if target_node.has_method("set_score"):
		score_updated.connect(target_node.set_score)

# Public API methods
func change_scene(scene_path: String) -> void:
	game_scene_service.change_scene(scene_manager, scene_path)

func load_level(level_num: int) -> void:
	game_scene_service.load_level(level_manager, level_num)

func request_ad_revive() -> bool:
	return _request_ad_revive_internal()

func request_ad_revive_from_ui() -> bool:
	return _request_ad_revive_internal()

# Shared ad-revive request path keeps UI and non-UI callers behaviorally identical.
func _request_ad_revive_internal() -> bool:
	return revive_service.request_ad_revive_internal(self, ad_manager)

# Centralized revive result handlers keep UI flows dependent on one completion signal.
func handle_ad_revive_success(_ad_type: String = "") -> void:
	revive_service.handle_ad_revive_success(self)

func handle_ad_revive_failure(_error_data: Variant = null) -> void:
	revive_service.handle_ad_revive_failure(self, _error_data)

func notify_ad_failed_to_load(ad_type: String, error_data: Variant) -> void:
	if ad_type == "wheel_spin":
		wheel_ad_spin_pending = false
	ad_failed_to_load.emit(ad_type, error_data)

func notify_ad_reward_granted(reward_type: String) -> void:
	ad_reward_granted.emit(reward_type)

# Wheel helper API
func set_wheel_state_from_save(spins_used: int, free_used: int, ad_used: int, last_reset_day: int) -> void:
	wheel_spins_used_today = max(0, spins_used)
	wheel_free_spin_used_today = clampi(free_used, 0, DEFAULT_WHEEL_FREE_SPINS_PER_DAY)
	wheel_ad_spins_used_today = clampi(ad_used, 0, DEFAULT_WHEEL_AD_SPINS_PER_DAY)
	wheel_last_reset_day = max(0, last_reset_day)
	wheel_spins_used_today = maxi(
		wheel_spins_used_today,
		wheel_free_spin_used_today + wheel_ad_spins_used_today
	)
	wheel_spins_used_today = mini(wheel_spins_used_today, DEFAULT_WHEEL_MAX_SPINS_PER_DAY)
	reset_wheel_daily_if_needed()

func reset_wheel_state(force_reset_day: bool = false) -> void:
	wheel_spins_used_today = 0
	wheel_free_spin_used_today = 0
	wheel_ad_spins_used_today = 0
	wheel_ad_spin_pending = false
	if force_reset_day:
		wheel_last_reset_day = _get_today_key()

func reset_wheel_daily_if_needed() -> bool:
	var today_key := _get_today_key()
	if today_key != wheel_last_reset_day:
		reset_wheel_state()
		wheel_last_reset_day = today_key
		save_progress_if_enabled()
		return true
	return false

func get_wheel_daily_max_spins() -> int:
	return DEFAULT_WHEEL_MAX_SPINS_PER_DAY

func get_wheel_free_spin_limit() -> int:
	return DEFAULT_WHEEL_FREE_SPINS_PER_DAY

func get_wheel_ad_spin_limit() -> int:
	return DEFAULT_WHEEL_AD_SPINS_PER_DAY

func get_wheel_crystal_spin_cost() -> int:
	return DEFAULT_WHEEL_CRYSTAL_SPIN_COST

func get_wheel_spins_remaining() -> int:
	reset_wheel_daily_if_needed()
	return maxi(0, DEFAULT_WHEEL_MAX_SPINS_PER_DAY - wheel_spins_used_today)

func get_wheel_ad_spins_remaining() -> int:
	reset_wheel_daily_if_needed()
	return maxi(0, DEFAULT_WHEEL_AD_SPINS_PER_DAY - wheel_ad_spins_used_today)

func can_use_wheel_free_spin() -> bool:
	reset_wheel_daily_if_needed()
	return wheel_free_spin_used_today < DEFAULT_WHEEL_FREE_SPINS_PER_DAY and get_wheel_spins_remaining() > 0

func can_use_wheel_ad_spin() -> bool:
	reset_wheel_daily_if_needed()
	if wheel_free_spin_used_today < DEFAULT_WHEEL_FREE_SPINS_PER_DAY:
		return false
	return wheel_ad_spins_used_today < DEFAULT_WHEEL_AD_SPINS_PER_DAY and get_wheel_spins_remaining() > 0

func can_use_wheel_paid_spin() -> bool:
	reset_wheel_daily_if_needed()
	return get_wheel_spins_remaining() > 0 and can_afford("crystals", DEFAULT_WHEEL_CRYSTAL_SPIN_COST)

func try_use_wheel_free_spin() -> bool:
	if not can_use_wheel_free_spin():
		return false
	wheel_free_spin_used_today += 1
	wheel_spins_used_today += 1
	save_progress_if_enabled()
	return true

func try_use_wheel_paid_spin() -> Dictionary:
	if get_wheel_spins_remaining() <= 0:
		return {
			"ok": false,
			"error": "limit",
			"message": "No spins remaining today."
		}
	if not can_afford("crystals", DEFAULT_WHEEL_CRYSTAL_SPIN_COST):
		return {
			"ok": false,
			"error": "currency",
			"message": "Not enough crystals."
		}
	deduct_currency("crystals", DEFAULT_WHEEL_CRYSTAL_SPIN_COST)
	wheel_spins_used_today += 1
	save_progress_if_enabled()
	return {"ok": true}

func request_wheel_ad_spin() -> Dictionary:
	reset_wheel_daily_if_needed()
	if wheel_ad_spin_pending:
		return {
			"ok": false,
			"error": "pending",
			"message": "Ad already in progress."
		}
	if not can_use_wheel_ad_spin():
		return {
			"ok": false,
			"error": "limit",
			"message": "No ad spins remaining today."
		}
	if not ad_manager or not ad_manager.is_initialized:
		return {
			"ok": false,
			"error": "unavailable",
			"message": "Ads not available."
		}
	wheel_ad_spin_pending = true
	ad_manager.request_reward_ad("wheel_spin")
	return {"ok": true}

func consume_wheel_ad_spin_reward() -> bool:
	if not wheel_ad_spin_pending:
		return false
	wheel_ad_spin_pending = false
	reset_wheel_daily_if_needed()
	if get_wheel_spins_remaining() <= 0:
		return false
	if wheel_ad_spins_used_today >= DEFAULT_WHEEL_AD_SPINS_PER_DAY:
		return false
	wheel_ad_spins_used_today += 1
	wheel_spins_used_today += 1
	save_progress_if_enabled()
	return true

func cancel_wheel_ad_spin_pending() -> void:
	wheel_ad_spin_pending = false

func _get_today_key() -> int:
	var date := Time.get_date_dict_from_system()
	return int(date.get("year", 0)) * 10000 + int(date.get("month", 0)) * 100 + int(date.get("day", 0))

# Revive flow restores one life by default unless a caller explicitly overrides it.
func revive_player(lives: int = 1) -> void:
	player_manager.revive_player(lives)

func spawn_player(lives: int) -> void:
	player_manager.spawn_player(lives)

func activate_shadow_mode(duration: float) -> void:
	request_shadow_mode_activate(duration, "GameManager.activate_shadow_mode")

func get_super_mode_duration() -> float:
	var player_balance: Dictionary = get_game_settings_section("player_balance")
	return float(player_balance.get("super_mode_duration", 2.0))

func get_shadow_mode_duration() -> float:
	var player_balance: Dictionary = get_game_settings_section("player_balance")
	return float(player_balance.get("shadow_mode_duration", 3.5))

func unlock_shadow_mode() -> void:
	level_manager.unlock_shadow_mode()

func is_level_unlocked(level: int) -> bool:
	return level_manager.is_level_unlocked(level)

func is_level_completed(level: int) -> bool:
	return level_manager.is_level_completed(level)

func get_current_level() -> int:
	return game_scene_service.get_current_level(level_manager)

func get_map_scene_path() -> String:
	return game_scene_service.get_map_scene_path(scene_manager)

func is_shadow_mode_enabled() -> bool:
	return shadow_mode_state.shadow_mode_enabled

func save_progress() -> void:
	economy_service.save_progress(save_manager)

func save_progress_if_enabled() -> void:
	economy_service.save_progress_if_enabled(save_manager)

func reset_player_stats() -> void:
	if player_manager:
		player_manager.reset_player_stats()

func hide_banner_ad_if_initialized() -> void:
	if ad_manager and ad_manager.is_initialized:
		ad_manager.hide_banner_ad()

func is_ad_revive_pending() -> bool:
	return ad_manager != null and ad_manager.ad_revive_pending

func reset_ad_revive_state() -> void:
	if not ad_manager:
		return
	# Prefer centralized AdManager cleanup when available.
	if ad_manager.has_method("reset_revive_state"):
		ad_manager.reset_revive_state()
	else:
		ad_manager.ad_revive_pending = false
		ad_manager.revive_type = "none"
		ad_manager.selected_ad_type = ""
		ad_manager.is_ad_showing = false

func get_start_scene_path() -> String:
	return game_scene_service.get_start_scene_path(scene_manager)

func set_level_game_over_screen_active(active: bool) -> void:
	game_scene_service.set_level_game_over_screen_active(level_manager, active)

# Difficulty selection methods
func set_current_difficulty(difficulty: FormationEnums.DifficultyLevel) -> void:
	current_difficulty = difficulty

# Save/load helper accessors keep persistence logic decoupled from manager internals.
func has_level_state() -> bool:
	return progress_service.has_level_state(level_manager)

func has_player_state() -> bool:
	return progress_service.has_player_state(player_manager)

func can_persist_progress() -> bool:
	return progress_service.can_persist_progress(level_manager, player_manager)

func get_unlocked_levels_for_save() -> int:
	return progress_service.get_unlocked_levels_for_save(level_manager)

func set_unlocked_levels_from_save(value: Variant) -> void:
	progress_service.set_unlocked_levels_from_save(level_manager, value)

func get_shadow_mode_unlocked_for_save() -> bool:
	return progress_service.get_shadow_mode_unlocked_for_save(shadow_mode_state)

func get_shadow_mode_tutorial_shown_for_save() -> bool:
	return progress_service.get_shadow_mode_tutorial_shown_for_save(shadow_mode_state)

func get_completed_levels_for_save() -> Array:
	return progress_service.get_completed_levels_for_save(level_manager)

func set_completed_levels_from_save(value: Variant) -> void:
	progress_service.set_completed_levels_from_save(level_manager, value)

func get_selected_ship_id_for_save() -> String:
	return progress_service.get_selected_ship_id_for_save(player_manager)

func set_selected_ship_id_from_save(value: Variant) -> void:
	progress_service.set_selected_ship_id_from_save(player_manager, value)

func reset_level_progress() -> void:
	progress_service.reset_level_progress(level_manager)

# Config passthrough helpers avoid direct ConfigLoader coupling in other managers.
func get_game_setting(key: String, default_value: Variant) -> Variant:
	return config_service.get_game_setting(ConfigLoader, key, default_value)

func get_game_settings_section(key: String) -> Dictionary:
	return config_service.get_game_settings_section(ConfigLoader, key)

func get_player_setting(key: String, default_value: Variant) -> Variant:
	return config_service.get_player_setting(ConfigLoader, key, default_value)

func get_upgrade_setting(key: String, default_value: Variant) -> Variant:
	return config_service.get_upgrade_setting(ConfigLoader, key, default_value)

func get_boss_reward_for_level(level_num: int) -> Dictionary:
	return config_service.get_boss_reward_for_level(ConfigLoader, level_num)

func get_config_ships_data() -> Array:
	return config_service.get_config_ships_data(ConfigLoader)

func get_config_satellites_data() -> Array:
	return config_service.get_config_satellites_data(ConfigLoader)

func is_boss_level_completed(level_num: int) -> bool:
	return progress_service.is_boss_level_completed(save_manager, level_num)

func mark_boss_level_completed(level_num: int) -> bool:
	return progress_service.mark_boss_level_completed(save_manager, level_num)

func mark_level_completed_if_needed(level_num: int) -> bool:
	if not progress_service.mark_level_completed_if_needed(level_manager, level_num):
		return false
	level_star_earned.emit(level_num)
	return true

func unlock_level_if_needed(level_num: int) -> bool:
	if not progress_service.unlock_level_if_needed(level_manager, level_num):
		return false
	level_unlocked.emit(level_num)
	return true

func can_afford(currency_type: String, cost: int) -> bool:
	return economy_service.can_afford(self, currency_type, cost)

func deduct_currency(currency_type: String, amount: int) -> void:
	economy_service.deduct_currency(self, save_manager, currency_type, amount)

var coins_collected_this_level: int:
	get: return level_currency_state.coins_collected_this_level
	set(value):
		level_currency_state.coins_collected_this_level = value

var crystals_collected_this_level: int:
	get: return level_currency_state.crystals_collected_this_level
	set(value):
		level_currency_state.crystals_collected_this_level = value

func add_currency(currency_type: String, amount: int) -> void:
	economy_service.add_currency(self, save_manager, currency_type, amount)

# Add this function to reset the collected currencies when starting a new level
func reset_level_currencies() -> void:
	coins_collected_this_level = 0
	crystals_collected_this_level = 0

## Shared level completion reward calculation.
func calculate_level_completion_rewards(level_num: int) -> Dictionary:
	var base_coins = get_upgrade_setting("level_completion_base_coins", 200)
	var base_crystals = get_upgrade_setting("level_completion_base_crystals", 10)
	var level_multiplier = pow(float(level_num), 0.75)
	return {
		"coins": int(base_coins * level_multiplier),
		"crystals": int(base_crystals * level_multiplier)
	}

# New function to pause the game during ad revive
func pause_for_ad_revive() -> void:
	if not game_over or level_manager.is_level_just_completed:
		return
	is_paused = true  # Pauses the game tree


# New function to resume the game after ad revive
func resume_after_ad_revive() -> void:
	if is_paused and not level_manager.is_level_just_completed:
		is_paused = false  # Resumes the game tree


# Handle revive completion signal
func _on_revive_completed(_success: bool) -> void:
	resume_after_ad_revive()

# Notify when ship stats are updated
func notify_ship_stats_updated(ship_id: String, new_damage: int) -> void:
	ship_stats_updated.emit(ship_id, new_damage)
	# Update PlayerManager's base damage for the current ship
	if player_manager.selected_ship_id == ship_id:
		player_manager.update_current_ship_damage(new_damage)

# Notify when satellite stats are updated
func notify_satellite_stats_updated(satellite_id: String, damage_bonus: int) -> void:
	satellite_stats_updated.emit(satellite_id, damage_bonus)

# Notify when enemy is killed for shadow mode charging
func notify_enemy_killed(enemy: Node) -> void:
	enemy_killed.emit(enemy)

func save_map_camera_position(camera_position: Vector2) -> void:
	saved_map_camera_position = camera_position
	has_saved_map_camera_position = true

func get_saved_map_camera_position(default_position: Vector2 = Vector2.ZERO) -> Vector2:
	if has_saved_map_camera_position:
		return saved_map_camera_position
	return default_position

# Handle prepare_map_scene signal
func _on_prepare_map_scene() -> void:
	# This function is called before transitioning to the map scene
	# It ensures stars are updated before the scene transition
	pass

# Debug utility: instantly complete the current level
# Only active when Debug Mode is on (debug builds only)
func dev_win() -> void:
	if not debug_mode:
		return

	# Only process if we're in a level scene
	var current_scene = get_tree().current_scene
	if not current_scene:
		return

	print("[DEV_WIN] Triggering instant level completion")

	# Trigger the same flow as a legitimate win
	# 1. Get current level
	var current_level = get_current_level()
	if current_level > 0:
		# 2. Clear any existing enemies and bullets to prevent interference
		_clear_all_enemies_and_bullets()

		# 3. Trigger level completion through LevelManager
		# This will: emit victory_pose, show UI, calculate score, transition, etc.
		level_manager.complete_level(current_level)
		DebugFlags.debug_print("[DEV_WIN] Level %d completed" % current_level)
	else:
		DebugFlags.debug_print("[DEV_WIN] Not in a level (level=%d), ignoring dev_win request" % current_level)

# Helper to clear enemies and bullets for clean level completion
func _clear_all_enemies_and_bullets() -> void:
	# Clear all enemies
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if enemy and is_instance_valid(enemy):
			enemy.queue_free()

	# Clear all enemy bullets
	for bullet in get_tree().get_nodes_in_group("EnemyBullet"):
		if bullet and is_instance_valid(bullet):
			bullet.queue_free()

	# Clear all boss enemies
	for boss in get_tree().get_nodes_in_group("Boss"):
		if boss and is_instance_valid(boss):
			boss.queue_free()

	DebugFlags.debug_print("[DEV_WIN] Cleared enemies and bullets")
