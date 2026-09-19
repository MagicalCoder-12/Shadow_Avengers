extends Node2D
class_name WaveManager

const COINS = preload("res://Resources/Coins.tscn")
const CRYSTAL = preload("res://Resources/Crystal.tscn")
const BOSS_MUSIC_STREAM := preload("res://Assets/Music/Boss_music.mp3")
const POWERUP_SCENES = [
	preload("res://Powerups/Attack_boost_powerup.tscn"),
	preload("res://Powerups/SuperMode.tscn"),
	preload("res://Powerups/Health.tscn")
]

# Import formation_enums to access shared enums
const FormationEnums = preload("res://EnemyManager/Scripts/formation_enums.gd")

# Signals for wave progression and events
signal wave_started(current_wave: int, total_waves: int)
signal wave_cleared(current_wave: int, wave_config: WaveConfig)
signal all_waves_cleared()
signal enemy_spawned(enemy: Node2D)
signal enemy_killed(enemy: Node2D)

# Exported properties
@export var wave_delay: float = 1.5
@export var formation_manager_scene: PackedScene

@onready var boss_music: AudioStreamPlayer = get_node_or_null("BossMusic")

# Core wave management variables
var waves: Array[WaveConfig] = []
var current_wave: int = 0
var current_level: int = 1
var total_waves: int = 0
var wave_in_progress: bool = false
var waiting_for_next_wave: bool = false
var has_completed_level: bool = false
var _cleaning_up: bool = false  # True during _cleanup_wave to prevent _on_enemy_killed races

# Enemy tracking - active_enemies is now the single source of truth
var active_enemies: Array[Node2D] = []
var _connected_enemies: Array[Node2D] = []
var enemies_alive: int = 0  # Derived from active_enemies.size() - updated only in helper functions
var current_wave_config: WaveConfig = null
var _enemy_reward_payloads: Dictionary = {}

# Formation and boss management
var formation_manager: FormationManager = null
var active_formations: Array[FormationManager] = []
var current_boss: Node2D = null

# Timing
var wave_start_time: float = 0.0
var wave_completion_time: float = 0.0

# Game state references
var game_manager: Node = null

# New variables for dynamic wave progression
var player_performance: float = 0.5  # 0.0 (struggling) to 1.0 (excelling)
var elite_enemy_spawned: bool = false
var swarm_spawned: bool = false

func _ready():
	# Start the stuck check timer
	stuck_check_timer.start()
	game_manager = GameManager
	_ensure_boss_music_player()
	if boss_music == null and GameManager.debug_mode:
		push_warning("WaveManager: BossMusic node is missing; boss music playback will be skipped.")
	if GameManager.debug_mode:
		print("WaveManager: Ready for level %d" % current_level)

func set_waves(wave_configs: Array[WaveConfig]) -> void:
	waves = wave_configs
	total_waves = waves.size()
	current_wave = 0
	if GameManager.debug_mode:
		print("WaveManager: Set %d waves for level %d" % [total_waves, current_level])

func start_waves() -> void:
	if waves.is_empty():
		push_error("WaveManager: No waves to start")
		return

	current_wave = 0
	wave_in_progress = false
	waiting_for_next_wave = false
	has_completed_level = false

	if GameManager.debug_mode:
		print("WaveManager: Starting waves for level %d" % current_level)

	start_next_wave()

# --- New Methods for Dynamic Wave Progression ---

func _adjust_wave_difficulty_based_on_selection() -> void:
	# Apply the difficulty selected by the player
	if GameManager and GameManager.current_difficulty != null:
		current_wave_config.difficulty = GameManager.current_difficulty
		if GameManager.debug_mode:
			print("WaveManager: Applied selected difficulty: %s" % FormationEnums.DifficultyLevel.keys()[current_wave_config.difficulty])
	else:
		# Fallback to performance-based adjustment
		_adjust_wave_difficulty(player_performance)

func _adjust_wave_difficulty(new_player_performance: float):
	# Update class-level player_performance
	player_performance = clamp(new_player_performance, 0.0, 1.0)

	# Modify enemy count, health, and shooting frequency based on player performance
	if not current_wave_config:
		if GameManager.debug_mode:
			print("WaveManager: No wave config to adjust difficulty")
		return

	if player_performance > 0.7:  # Player is doing well
		# Increase difficulty
		current_wave_config.difficulty = FormationEnums.DifficultyLevel.HARD
		if GameManager.debug_mode:
			print("WaveManager: Difficulty set to HARD (player_performance: %.2f)" % player_performance)
	elif player_performance < 0.3:  # Player is struggling
		# Decrease difficulty
		current_wave_config.difficulty = FormationEnums.DifficultyLevel.EASY
		if GameManager.debug_mode:
			print("WaveManager: Difficulty set to EASY (player_performance: %.2f)" % player_performance)
	else:
		# Keep normal difficulty
		current_wave_config.difficulty = FormationEnums.DifficultyLevel.NORMAL
		if GameManager.debug_mode:
			print("WaveManager: Difficulty set to NORMAL (player_performance: %.2f)" % player_performance)

func _trigger_event_wave(event_type: String):
	# Spawn special enemy formations based on events
	# Examples: Boss rushes, swarm attacks, elite enemy appearances
	match event_type:
		"swarm":
			_spawn_enemy_swarm(10, FormationEnums.EnemyType.MOB1)
		"elite":
			_spawn_elite_enemy()
		_:
			if GameManager.debug_mode:
				print("WaveManager: Unknown event wave type: %s" % event_type)

func _spawn_elite_enemy():
	# Create an elite enemy with enhanced stats and rewards
	if not formation_manager_scene:
		push_error("WaveManager: No formation manager scene assigned")
		return

	# Create a temporary wave config for the elite enemy
	var elite_config = WaveConfig.new()
	elite_config.enemy_type = FormationEnums.EnemyType.ELITE_ENEMY
	elite_config.formation_type = FormationEnums.FormationType.CIRCLE
	elite_config.entry_pattern = FormationEnums.EntryPattern.TOP_DIVE
	elite_config.difficulty = FormationEnums.DifficultyLevel.HARD
	elite_config.formation_center = Vector2(640, 300)
	elite_config.formation_radius = 100.0

	# Create formation manager for elite enemy
	var elite_formation_manager = formation_manager_scene.instantiate() as FormationManager
	if not elite_formation_manager:
		push_error("WaveManager: Failed to instantiate formation manager for elite enemy")
		return

	# Ensure we're in the scene tree before trying to access current_scene
	if not get_tree():
		push_error("WaveManager: Not in scene tree, cannot spawn elite enemy")
		elite_formation_manager.queue_free()
		return

	# Get the target parent - prefer current_scene, fall back to our parent
	var target_parent = SceneSpawnService._get_safe_current_scene() if SceneSpawnService._get_safe_current_scene() else get_parent()
	if not target_parent:
		push_error("WaveManager: No valid parent found for elite enemy")
		elite_formation_manager.queue_free()
		return

	# Add to scene and connect signals
	target_parent.call_deferred("add_child", elite_formation_manager)
	active_formations.append(elite_formation_manager)

	if elite_formation_manager.has_signal("enemy_spawned"):
		elite_formation_manager.enemy_spawned.connect(_on_enemy_spawned)
	if elite_formation_manager.has_signal("formation_complete"):
		elite_formation_manager.formation_complete.connect(_on_formation_complete)
	if elite_formation_manager.has_signal("all_enemies_destroyed"):
		elite_formation_manager.all_enemies_destroyed.connect(_on_all_enemies_destroyed)

	# Start formation spawning after FormationManager is added to scene tree
	elite_formation_manager.call_deferred("spawn_formation", elite_config)

	elite_enemy_spawned = true

	if GameManager.debug_mode:
		print("WaveManager: Elite enemy spawned")

func _spawn_enemy_swarm(count: int, enemy_type: FormationEnums.EnemyType):
	# Spawn a swarm of enemies
	if not formation_manager_scene:
		push_error("WaveManager: No formation manager scene assigned")
		return

	# Create a temporary wave config for the swarm
	var swarm_config = WaveConfig.new()
	swarm_config.enemy_type = enemy_type
	swarm_config.formation_type = FormationEnums.FormationType.CLUSTER
	swarm_config.entry_pattern = FormationEnums.EntryPattern.STAGGERED
	swarm_config.difficulty = FormationEnums.DifficultyLevel.NORMAL
	swarm_config.formation_center = Vector2(640, 500)
	swarm_config.formation_radius = 150.0
	swarm_config.count = count  # Assuming WaveConfig has a count property

	# Create formation manager for swarm
	var swarm_formation_manager = formation_manager_scene.instantiate() as FormationManager
	if not swarm_formation_manager:
		push_error("WaveManager: Failed to instantiate formation manager for swarm")
		return

	# Ensure we're in the scene tree before trying to access current_scene
	if not get_tree():
		push_error("WaveManager: Not in scene tree, cannot spawn swarm")
		swarm_formation_manager.queue_free()
		return

	# Get the target parent - prefer current_scene, fall back to our parent
	var target_parent = SceneSpawnService._get_safe_current_scene() if SceneSpawnService._get_safe_current_scene() else get_parent()
	if not target_parent:
		push_error("WaveManager: No valid parent found for swarm")
		swarm_formation_manager.queue_free()
		return

	# Add to scene and connect signals
	target_parent.call_deferred("add_child", swarm_formation_manager)
	active_formations.append(swarm_formation_manager)

	if swarm_formation_manager.has_signal("enemy_spawned"):
		swarm_formation_manager.enemy_spawned.connect(_on_enemy_spawned)
	if swarm_formation_manager.has_signal("formation_complete"):
		swarm_formation_manager.formation_complete.connect(_on_formation_complete)
	if swarm_formation_manager.has_signal("all_enemies_destroyed"):
		swarm_formation_manager.all_enemies_destroyed.connect(_on_all_enemies_destroyed)

	# Start formation spawning after FormationManager is added to scene tree
	swarm_formation_manager.call_deferred("spawn_formation", swarm_config)

	swarm_spawned = true

	if GameManager.debug_mode:
		print("WaveManager: Enemy swarm spawned with %d enemies" % count)

func start_next_wave() -> void:
	if current_wave >= total_waves:
		if GameManager.debug_mode:
			print("WaveManager: All waves completed for level %d" % current_level)
		print("WaveManager: Emitting all_waves_cleared signal")
		all_waves_cleared.emit()
		return

	if wave_in_progress or waiting_for_next_wave:
		if GameManager.debug_mode:
			print("WaveManager: Cannot start wave - already in progress or waiting")
		return

	current_wave_config = waves[current_wave]
	wave_in_progress = true
	wave_start_time = Time.get_unix_time_from_system()

	# Apply the selected difficulty instead of performance-based adjustment
	_adjust_wave_difficulty_based_on_selection()

	if GameManager.debug_mode:
		print("WaveManager: Starting wave %d/%d (Level: %d, Difficulty: %s)" % [current_wave + 1, total_waves, current_level, FormationEnums.DifficultyLevel.keys()[current_wave_config.difficulty]])

	wave_started.emit(current_wave + 1, total_waves)

	# Spawn wave based on type
	if current_wave_config.is_boss_wave():
		_spawn_boss_wave()
	else:
		_spawn_normal_wave()

func _spawn_normal_wave() -> void:
	if not formation_manager_scene:
		push_error("WaveManager: No formation manager scene assigned")
		return

	# Create formation manager
	formation_manager = formation_manager_scene.instantiate() as FormationManager
	if not formation_manager:
		push_error("WaveManager: Failed to instantiate formation manager")
		return

	# Ensure we're in the scene tree before trying to access current_scene
	if not get_tree():
		push_error("WaveManager: Not in scene tree, cannot spawn formation manager")
		formation_manager.queue_free()
		return

	# Get the target parent - prefer current_scene, fall back to our parent
	var target_parent = SceneSpawnService._get_safe_current_scene() if SceneSpawnService._get_safe_current_scene() else get_parent()
	if not target_parent:
		push_error("WaveManager: No valid parent found for formation manager")
		formation_manager.queue_free()
		return

	# Add to scene and connect signals
	target_parent.call_deferred("add_child", formation_manager)
	active_formations.append(formation_manager)

	if formation_manager.has_signal("enemy_spawned"):
		formation_manager.enemy_spawned.connect(_on_enemy_spawned)
	if formation_manager.has_signal("formation_complete"):
		formation_manager.formation_complete.connect(_on_formation_complete)
	if formation_manager.has_signal("all_enemies_destroyed"):
		formation_manager.all_enemies_destroyed.connect(_on_all_enemies_destroyed)

	# Start formation spawning after FormationManager is added to scene tree
	formation_manager.call_deferred("spawn_formation", current_wave_config)

	if GameManager.debug_mode:
		print("WaveManager: Normal wave spawning started")

func _spawn_boss_wave() -> void:
	if not current_wave_config or not current_wave_config.boss_scene:
		push_error("WaveManager: Boss wave has no boss scene configured")
		_complete_wave()
		return

	# Ensure we're in the scene tree
	if not get_tree():
		push_error("WaveManager: Not in scene tree, cannot spawn boss")
		_complete_wave()
		return

	# Play boss music when boss wave starts
	_play_boss_music()

	# Get the target parent - prefer current_scene, fall back to our parent
	var target_parent = SceneSpawnService._get_safe_current_scene() if SceneSpawnService._get_safe_current_scene() else get_parent()
	if not target_parent:
		push_error("WaveManager: No valid parent found for boss")
		_complete_wave()
		return

	# Instantiate and spawn the boss ABOVE the screen
	var boss_instance = current_wave_config.boss_scene.instantiate()
	if not boss_instance:
		push_error("WaveManager: Failed to instantiate boss scene")
		_complete_wave()
		return

	var viewport_rect = get_viewport().get_visible_rect()
	var boss_position = Vector2(current_wave_config.formation_center.x, -200)  # Spawn off-screen above
	# Clamp x to screen bounds
	boss_position.x = clamp(boss_position.x, 100, viewport_rect.size.x - 100)
	boss_instance.global_position = boss_position

	# Add boss to scene deferred
	target_parent.call_deferred("add_child", boss_instance)

	# Wait a frame for it to be in the tree, then connect
	call_deferred("_connect_boss_signals", boss_instance)

	# Track the boss (but don't increment enemies_alive yet; wait for descent)
	current_boss = boss_instance
	_register_enemy(boss_instance)
	enemies_alive = 0  # Defer this until descent completes

	enemy_spawned.emit(boss_instance)

	if GameManager.debug_mode:
		print("WaveManager: Boss spawned off-screen at %s (Wave: %d, Level: %d)" % [boss_instance.global_position, current_wave + 1, current_level])

func _play_boss_music() -> void:
	_ensure_boss_music_player()
	if boss_music:
		boss_music.play()
	elif GameManager.debug_mode:
		push_warning("WaveManager: Cannot play boss music because BossMusic is null.")

	if AudioManager:
		_start_boss_audio()
		if GameManager.debug_mode:
			print("Boss music started by WaveManager")
	elif GameManager.debug_mode:
		push_warning("WaveManager: AudioManager is unavailable; boss audio bus isolation skipped.")

func _ensure_boss_music_player() -> void:
	if boss_music and is_instance_valid(boss_music):
		if boss_music.stream == null:
			boss_music.stream = BOSS_MUSIC_STREAM
		return

	boss_music = get_node_or_null("BossMusic")
	if boss_music and is_instance_valid(boss_music):
		if boss_music.stream == null:
			boss_music.stream = BOSS_MUSIC_STREAM
		return

	boss_music = AudioStreamPlayer.new()
	boss_music.name = "BossMusic"
	boss_music.stream = BOSS_MUSIC_STREAM
	add_child(boss_music)
	if not boss_music.finished.is_connected(_on_boss_music_finished):
		boss_music.finished.connect(_on_boss_music_finished)

func _connect_boss_signals(boss: Node2D) -> void:
	if not is_instance_valid(boss):
		return

	# Connect death signal
	if boss.has_signal("died"):
		var callable = _on_enemy_killed.bind(boss)
		if not boss.died.is_connected(callable):
			boss.died.connect(callable)

	elif boss.has_signal("boss_defeated"):
		var callable = _on_enemy_killed.bind(boss)
		if not boss.boss_defeated.is_connected(callable):
			boss.boss_defeated.connect(callable)

	if boss.has_signal("enemy_died"):
		var callable2 = _on_enemy_died.bind(boss)
		if not boss.enemy_died.is_connected(callable2):
			boss.enemy_died.connect(callable2)

	# Connect phase change signal for invincibility
	if boss.has_signal("phase_changed"):
		boss.phase_changed.connect(_on_boss_phase_changed.bind(boss))

	# Connect descent completed signal to start full tracking
	if boss.has_signal("descent_completed"):
		boss.descent_completed.connect(func():
			enemies_alive = 1
			if GameManager.debug_mode:
				print("WaveManager: Boss descent complete - now tracking as alive enemy")
		)

func _on_boss_phase_changed(_phase, boss: Node2D) -> void:
	# Make boss invincible for 5 seconds after phase change
	if boss.has_method("set_invincible"):
		boss.set_invincible(true)

		# Wait 5 seconds then make boss vulnerable again
		await get_tree().create_timer(5.0).timeout

		# Guard: boss or wave manager may have been freed during the await.
		if is_instance_valid(boss) and is_instance_valid(self) and boss.has_method("set_invincible"):
			boss.set_invincible(false)

# --- Enemy Registration Helpers (Single Source of Truth) ---

func _register_enemy(enemy: Node2D) -> void:
	"""Centralized enemy addition - ensures no duplicates and proper signal connection"""
	if not is_instance_valid(enemy):
		return

	# Prevent duplicate registration
	if enemy in active_enemies:
		if GameManager.debug_mode:
			print("WaveManager: Enemy already registered, skipping: %s" % enemy.name)
		return

	# Add to tracking arrays
	active_enemies.append(enemy)
	_connected_enemies.append(enemy)

	# Connect required signals in ONE place
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_killed.bind(enemy))
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died.bind(enemy))

	# Update derived counter
	enemies_alive = active_enemies.size()

	# Emit spawn signal and sync state
	enemy_spawned.emit(enemy)
	_sync_enemy_shadow_state(enemy)

func _unregister_enemy(enemy: Node2D) -> void:
	"""Centralized enemy removal - ensures clean up happens exactly once"""
	if not is_instance_valid(enemy):
		return

	# Clean up invalid enemies first to prevent stale references
	active_enemies = active_enemies.filter(func(e): return is_instance_valid(e))

	# Remove from active tracking if present
	if enemy in active_enemies:
		active_enemies.erase(enemy)
		enemy_killed.emit(enemy)

		# Remove from connected enemies list
		if enemy in _connected_enemies:
			_connected_enemies.erase(enemy)

		# If this was the boss, restore audio volumes
		if enemy == current_boss:
			_on_boss_defeated()
	else:
		if GameManager.debug_mode:
			print("WaveManager: Attempted to process killed enemy that is invalid or not in active_enemies")

	# Update derived counter
	enemies_alive = max(0, active_enemies.size())

# --- Wave Completion Unification ---

func _check_wave_completion() -> void:
	"""Single decision point for wave completion - checks all conditions before calling _complete_wave()"""
	# Prevent double completion
	if not wave_in_progress or waiting_for_next_wave:
		return

	# Primary completion condition: no enemies alive
	if enemies_alive <= 0:
		if GameManager.debug_mode:
			print("WaveManager: Wave completion conditions met - calling _complete_wave()")
			print("WaveManager: Calling _complete_wave from _check_wave_completion")
		_complete_wave()
		return

	# Additional validation - ensure we have no valid enemies remaining
	var valid_enemy_count = 0
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			valid_enemy_count += 1

	if valid_enemy_count == 0 and enemies_alive > 0:
		# Clean up discrepancy and complete wave
		if GameManager.debug_mode:
			print("WaveManager: Detected discrepancy - forcing completion with %d tracked but 0 valid enemies" % enemies_alive)
		enemies_alive = 0
		_complete_wave()

# --- Audio Isolation ---

func _start_boss_audio() -> void:
	"""Helper to start boss audio with proper volume adjustments"""
	if AudioManager:
		AudioManager.lower_bus_volumes_except(["Boss", "Master"], -20.0)
		AudioManager.mute_bus("Bullet", true)

func _stop_boss_audio() -> void:
	"""Helper to stop boss audio and restore normal volumes"""
	if AudioManager:
		AudioManager.restore_bus_volumes()
		AudioManager.mute_bus("Bullet", false)

# --- Reward Handling Polish ---

func _consume_enemy_reward(enemy: Node2D) -> void:
	"""Consume enemy reward exactly once, ensuring idempotent reward handling"""
	var payload = _enemy_reward_payloads.get(enemy.get_instance_id(), {})
	if payload and not payload.get("is_boss", false):
		_apply_enemy_rewards(payload)
		# Notify GameManager for shadow mode charging (matches previous timing)
		if game_manager and is_instance_valid(enemy):
			game_manager.notify_enemy_killed(enemy)

	# Immediately remove the payload to prevent double consumption
	_enemy_reward_payloads.erase(enemy.get_instance_id())

func _on_enemy_spawned(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return

	_register_enemy(enemy)

	if GameManager.debug_mode:
		print("WaveManager: Enemy spawned - Total alive: %d (Wave: %d, Level: %d)" % [enemies_alive, current_wave + 1, current_level])

	# Verify count
	_verify_enemy_count()

func _on_formation_complete() -> void:
	if GameManager.debug_mode:
		print("WaveManager: Formation complete for wave %d" % (current_wave + 1))

func _on_all_enemies_destroyed() -> void:
	if GameManager.debug_mode:
		print("WaveManager: All enemies destroyed for wave %d" % (current_wave + 1))
	# Check for wave completion after all enemies destroyed
	_check_wave_completion()

func _verify_enemy_count() -> void:
	# Clean up invalid enemies first
	active_enemies = active_enemies.filter(func(e): return is_instance_valid(e) and e.is_alive)

	var valid_count = active_enemies.size()

	# Update enemies_alive to match valid_count if there's a discrepancy
	if enemies_alive != valid_count:
		if GameManager.debug_mode:
			print("WaveManager: Count mismatch detected - enemies_alive: %d, valid_count: %d (Wave: %d, Level: %d)" % [enemies_alive, valid_count, current_wave + 1, current_level])

		# Only log as error if the discrepancy is significant (> 1)
		if abs(enemies_alive - valid_count) > 1:
			push_error("WaveManager: Count mismatch - enemies_alive: %d, valid_count: %d (Wave: %d, Level: %d)" % [enemies_alive, valid_count, current_wave + 1, current_level])
		else:
			push_warning("WaveManager: Minor count mismatch - enemies_alive: %d, valid_count: %d (Wave: %d, Level: %d)" % [enemies_alive, valid_count, current_wave + 1, current_level])

		enemies_alive = valid_count

func _on_enemy_killed(enemy: Node2D) -> void:
	# Skip kills during wave cleanup to prevent double-free races.
	if _cleaning_up or not wave_in_progress:
		return

	# Consume enemy reward exactly once
	_consume_enemy_reward(enemy)

	_unregister_enemy(enemy)

	# Verify our tracking
	_verify_enemy_count()

	# Check for wave completion after enemy removal
	_check_wave_completion()

func _on_enemy_died(payload: Dictionary, enemy: Node2D) -> void:
	if not payload:
		return
	_enemy_reward_payloads[enemy.get_instance_id()] = payload
	# Rewards are consumed from _on_enemy_killed() so they are applied once.

func _apply_enemy_rewards(payload: Dictionary) -> void:
	if not game_manager:
		return
	var base_score = int(payload.get("base_score", 0))
	var is_shadow_enemy = bool(payload.get("is_shadow_enemy", false))
	var shadow_multiplier = float(payload.get("shadow_score_multiplier", 1.0))
	var final_score = base_score
	if is_shadow_enemy:
		final_score = int(base_score * shadow_multiplier)
	game_manager.score += final_score

	# Get current level from GameManager
	var game_level = 1
	if game_manager.level_manager:
		game_level = game_manager.level_manager.get_current_level()

	# Get reward configuration
	var reward_config = {}
	if ConfigLoader and ConfigLoader.upgrade_settings:
		reward_config = ConfigLoader.upgrade_settings.get("enemy_drop_rewards", {})

	# Default values if config not found
	var coins_per_enemy = reward_config.get("coins_per_enemy", 15)
	var coin_drop_chance = reward_config.get("coin_drop_chance", 0.7)
	var crystal_drop_chance = reward_config.get("crystal_drop_chance", 0.2)
	var crystal_reward_per_drop = reward_config.get("crystal_reward_per_drop", 5)

	# Scale rewards based on level (higher levels give more rewards)
	var level_multiplier = pow(float(game_level), 0.5)  # Square root scaling
	var scaled_coins = int(coins_per_enemy * level_multiplier)
	var scaled_crystal_reward = int(crystal_reward_per_drop * level_multiplier)

	# Determine what to drop - either coins OR crystals, not both
	var drop_crystal = randf() < crystal_drop_chance
	var drop_coins = !drop_crystal && (randf() < coin_drop_chance)
	var drop_position = payload.get("global_position", Vector2.ZERO)

	# Drop coins if selected
	if drop_coins:
		# Drop coins - 1-2 coins per enemy with level scaling
		var coin_count = randi_range(1, 2)
		for i in range(coin_count):
			var coin = COINS.instantiate()
			coin.global_position = drop_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
			# Set the coin value based on the scaled reward
			if coin.has_method("set_value"):
				coin.set_value(scaled_coins)
			SceneSpawnService.call_deferred("spawn_child", coin)

	# Drop crystal if selected (instead of coins)
	elif drop_crystal:
		var crystal = CRYSTAL.instantiate()
		crystal.global_position = drop_position
		# Set the crystal value based on the scaled reward
		if crystal.has_method("set_value"):
			crystal.set_value(scaled_crystal_reward)
		SceneSpawnService.call_deferred("spawn_child", crystal)

		# Drop power-ups occasionally
		if randf() < 0.3:  # 30% chance to drop a power-up
			_drop_powerup(drop_position)

func _drop_powerup(drop_position: Vector2) -> void:
	# Instantiate and drop a random power-up
	var selected_scene = POWERUP_SCENES[randi() % POWERUP_SCENES.size()]
	var powerup = selected_scene.instantiate()
	powerup.global_position = drop_position
	SceneSpawnService.call_deferred("spawn_child", powerup)

func _on_boss_defeated() -> void:
	if GameManager.debug_mode:
		print("WaveManager: Boss defeated, boss music stopped, audio volumes restored")

	_stop_boss_audio()

	# Check for wave completion after boss defeat
	_check_wave_completion()

func _complete_wave():
	if GameManager.debug_mode:
		print("WaveManager: _complete_wave() called - setting waiting_for_next_wave = true")

	wave_completion_time = Time.get_unix_time_from_system()
	var wave_duration = wave_completion_time - wave_start_time

	if GameManager.debug_mode:
		print("WaveManager: Wave %d completed in %.1f seconds (Level: %d)" % [current_wave + 1, wave_duration, current_level])

	wave_cleared.emit(current_wave + 1, current_wave_config)
	wave_in_progress = false
	waiting_for_next_wave = true

	_cleanup_wave()

	# Move to next wave
	current_wave += 1

	if GameManager.debug_mode:
		print("WaveManager: Starting wave delay timer for %f seconds" % wave_delay)

	# Create timer for next wave
	var timer = get_tree().create_timer(wave_delay, false)
	await timer.timeout

	if GameManager.debug_mode:
		print("WaveManager: Wave delay timer finished - setting waiting_for_next_wave = false")

	waiting_for_next_wave = false
	start_next_wave()

func _cleanup_wave():
	_cleaning_up = true

	# Clean up invalid enemies first
	var valid_enemies: Array[Node2D] = []
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			valid_enemies.append(enemy)
	active_enemies = valid_enemies

	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()

	# Clear all tracking arrays
	active_enemies.clear()
	_connected_enemies.clear()

	# Reset derived counter
	enemies_alive = 0

	for formation in active_formations:
		if is_instance_valid(formation):
			formation.queue_free()
	active_formations.clear()

	if formation_manager and is_instance_valid(formation_manager) and formation_manager.has_method("reset"):
		formation_manager.reset()

	current_boss = null
	_cleaning_up = false

# Timer to check for stuck wave periodically instead of every frame
@onready var stuck_check_timer: Timer = _create_stuck_check_timer()

func _create_stuck_check_timer() -> Timer:
	var timer = Timer.new()
	add_child(timer)
	timer.timeout.connect(_check_for_stuck_wave)
	timer.wait_time = 1.0  # Check every second instead of every frame
	return timer

func _check_for_stuck_wave():
	if wave_in_progress and not waiting_for_next_wave:
		# Check for stuck wave due to untracked enemy deaths
		var valid_enemies: Array[Node2D] = []
		var valid_count = 0
		for enemy in active_enemies:
			if is_instance_valid(enemy):
				valid_enemies.append(enemy)
				valid_count += 1
		if valid_count != enemies_alive:
			if GameManager.debug_mode:
				print("WaveManager: Mismatch detected - enemies_alive: %d, valid_enemies: %d (Wave: %d, Level: %d)" % [enemies_alive, valid_count, current_wave + 1, current_level])

			enemies_alive = valid_count
			active_enemies = valid_enemies

			if enemies_alive <= 0:
				if GameManager.debug_mode:
					print("WaveManager: Forcing wave completion due to no valid enemies remaining")
				_check_wave_completion()

func _exit_tree():
	# Clean up timer when node exits tree
	if stuck_check_timer:
		stuck_check_timer.stop()
		if stuck_check_timer.is_inside_tree():
			stuck_check_timer.queue_free()

func _on_shadow_mode_activated():
	if GameManager.debug_mode:
		print("WaveManager: Shadow mode activated")
	_notify_enemies_shadow_mode(true)

func _on_shadow_mode_deactivated():
	if GameManager.debug_mode:
		print("WaveManager: Shadow mode deactivated")
	_notify_enemies_shadow_mode(false)

func _notify_enemies_shadow_mode(active: bool) -> void:
	for enemy in active_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("on_shadow_mode_changed"):
			if enemy.get("is_alive") == false:
				continue
			enemy.on_shadow_mode_changed(active)

func _sync_enemy_shadow_state(enemy: Node2D) -> void:
	if not game_manager or not game_manager.level_manager:
		return
	if not is_instance_valid(enemy):
		return
	if enemy.has_method("on_shadow_mode_unlocked_changed"):
		enemy.on_shadow_mode_unlocked_changed(game_manager.level_manager.shadow_mode_unlocked)
	if enemy.has_method("on_shadow_mode_changed"):
		# Sync state without triggering activation effects
		enemy.is_shadow_mode_active = game_manager.level_manager.shadow_mode_enabled

func _on_boss_music_finished() -> void:
	_stop_boss_audio()
