extends Node

# === NODES ===
@onready var game_over_screen: Control = $"../CanvasLayer/GameOverScreen"
@onready var pause_menu: Control = $"../CanvasLayer/PauseMenu"
@onready var level_completed: Control = $"../CanvasLayer/LevelCompleted"
@onready var boss_clear: Control = $"../CanvasLayer/BossClear"
@onready var hud: Control = $"../CanvasLayer/HUD"
@onready var animation_player: AnimationPlayer = $"../AnimationPlayer"
@onready var wave_manager: WaveManager = $"../WaveManager"

# Wave Details UI
@onready var wave_details: Panel = $"../CanvasLayer/wave_Details"
@onready var wave_details_container: VBoxContainer = $"../CanvasLayer/wave_Details/VBoxContainer"
@onready var level_label: Label = $"../CanvasLayer/wave_Details/VBoxContainer/Level"
@onready var total_waves_label: Label = $"../CanvasLayer/wave_Details/VBoxContainer/Total_waves"

# === EXPORTED ===
@export var level_num: int = 1
# Array of WaveConfig resources defining the waves for this level
# Create WaveConfig resources using the WaveConfig.tscn template
# or load existing .tres files
@export var waves: Array[WaveConfig] = []
# === VARIABLES ===
var has_completed_level: bool = false
var level_game_over: bool = false
var waves_initialized: bool = false
var saved_shadow_charge: float = 0.0
var player_scene: PackedScene = preload("res://Ships/Player_Ship1.tscn")
var has_spawned_player: bool = false
var wave_details_tween: Tween = null

# Wave details display settings
const WAVE_DETAILS_DISPLAY_DURATION: float = 2.5
const WAVE_DETAILS_FADE_DURATION: float = 0.4

# Signals 
@warning_ignore("unused_signal")
signal Victory_pose()

# === READY ===
func _ready():
	# Add to LevelManager group
	game_over_screen.hide()
	pause_menu.hide()
	level_completed.hide()
	boss_clear.hide()
	level_game_over = GameManager.game_over

	# Ensure gameplay audio mix is applied for level scenes
	AudioManager.set_gameplay_mix(true)

	# Ensure background music is playing for this level
	var level_music: AudioStream = preload("res://Assets/Music/GameSong (mp3cut.net).mp3")
	if not AudioManager.background_player.playing or AudioManager.current_background_music != level_music:
		AudioManager.play_background_music(level_music, true)

	# Hide banner ad when entering a level
	if GameManager.ad_manager and GameManager.ad_manager.is_initialized:
		GameManager.ad_manager.hide_banner_ad()

	# HUD check
	if not hud:
		push_warning("HUD node not found")
	else:
		var shadow_button = hud.get_node_or_null("ShadowModeButton")
		if not shadow_button:
			push_warning("ShadowModeButton not found in HUD")
		if hud.has_signal("pause_requested"):
			var pause_requested_callable := Callable(self, "_on_pause_pressed")
			if not hud.is_connected("pause_requested", pause_requested_callable):
				hud.connect("pause_requested", pause_requested_callable)

	# Connect signals — each check is independent so all signals get connected
	if not GameManager.game_over_triggered.is_connected(_game_over_triggered):
		GameManager.game_over_triggered.connect(_game_over_triggered)
	if not GameManager.game_paused.is_connected(_on_game_paused):
		GameManager.game_paused.connect(_on_game_paused)
	if not GameManager.level_completed.is_connected(_on_level_completed):
		GameManager.level_completed.connect(_on_level_completed)
	if not GameManager.shadow_mode_activated.is_connected(_on_shadow_mode_activated):
		GameManager.shadow_mode_activated.connect(_on_shadow_mode_activated)
	if not GameManager.shadow_mode_deactivated.is_connected(_on_shadow_mode_deactivated):
		GameManager.shadow_mode_deactivated.connect(_on_shadow_mode_deactivated)

	if not wave_manager.wave_started.is_connected(hud._on_wave_started):
		wave_manager.wave_started.connect(hud._on_wave_started)

	# Connect wave_started signal to show wave details UI
	if not wave_manager.wave_started.is_connected(_on_wave_started):
		wave_manager.wave_started.connect(_on_wave_started)

	if not wave_manager.all_waves_cleared.is_connected(_on_wave_manager_all_waves_cleared):
		wave_manager.all_waves_cleared.connect(_on_wave_manager_all_waves_cleared)
	get_tree().get_root().connect("go_back_requested",_on_pause_pressed)
	
	# Connect game_over_screen signals for revive functionality
	if game_over_screen and game_over_screen.has_signal("player_revived"):
		if not game_over_screen.player_revived.is_connected(_on_player_revived):
			game_over_screen.player_revived.connect(_on_player_revived)
		
	if not GameManager.level_manager.level_loaded.is_connected(_on_level_loaded):
		GameManager.level_manager.level_loaded.connect(_on_level_loaded)

	# Hide wave details initially
	_hide_wave_details_instant()
	
	# Initialize waves
	_initialize_waves()
	
	# Fallback player spawning
	_check_and_spawn_player()

# === WAVE VALIDATION ===
func validate_wave_config(wave: WaveConfig, wave_index: int) -> bool:
	if not wave:
		push_warning("LevelManager: Wave %d is null" % (wave_index + 1))
		return false
	
	# Check enemy or boss scene
	var enemy_scene = wave.get_enemy_scene()
	if not enemy_scene or not enemy_scene.can_instantiate():
		push_warning("LevelManager: Wave %d has invalid or missing enemy/boss scene" % (wave_index + 1))
		return false
	
	# Check boss wave consistency
	if wave.is_boss_wave() and wave.get_enemy_count() != 1:
		push_warning("LevelManager: Wave %d is a boss wave but has enemy_count != 1 (%d)" % [wave_index + 1, wave.get_enemy_count()])
		return false
	
	# Check enemy density
	var valid_densities = ["Sparse", "Normal", "Dense", "Maximum"]
	if not wave.enemy_density in valid_densities:
		push_warning("LevelManager: Wave %d has invalid enemy_density '%s'" % [wave_index + 1, wave.enemy_density])
		return false
	
	# Check formation center
	if wave.formation_center.x < 0 or wave.formation_center.y < 0:
		push_warning("LevelManager: Wave %d has invalid formation_center %s" % [wave_index + 1, wave.formation_center])
		return false
	
	# Check formation type for non-boss waves
	if not wave.is_boss_wave():
		var valid_formations = formation_enums.FormationType.values()
		if not wave.get_formation_type() in valid_formations:
			push_warning("LevelManager: Wave %d has invalid formation_type %d" % [wave_index + 1, wave.get_formation_type()])
			return false
	
	# Check enemy type for non-boss waves
	if not wave.is_boss_wave():
		if not wave.enemy_type in formation_enums.EnemyType.values():
			push_warning("LevelManager: Wave %d has invalid enemy_type '%s'" % [wave_index + 1, wave.get_enemy_type_key()])
			return false
	
	if GameManager.debug_mode:
		var debug_string = wave.as_debug_string() if wave.has_method("as_debug_string") else "WaveConfig"
		print("LevelManager: Validated Wave %d: %s (Boss: %s, Enemy Count: %d)" % [
			wave_index + 1,
			debug_string,
			wave.is_boss_wave(),
			wave.get_enemy_count()
		])
	
	return true

# === WAVE INITIALIZATION ===
func _initialize_waves() -> void:
	if not waves:
		return
	
	for i in range(waves.size()):
		var wave = waves[i]
		if validate_wave_config(wave, i):
			if GameManager.debug_mode:
				var debug_string = wave.as_debug_string() if wave.has_method("as_debug_string") else "WaveConfig"
				print("LevelManager: Wave %d: Validated %s (Boss: %s, Enemy Count: %d)" % [
					i + 1,
					debug_string,
					wave.is_boss_wave(),
					wave.get_enemy_count()
				])
	
	# Send waves to WaveManager and start spawning
	wave_manager.set_waves(waves)
	wave_manager.current_level = level_num
	wave_manager.start_waves()
	waves_initialized = true
	if GameManager.debug_mode:
		print("LevelManager: Initialized %d waves for level %d" % [waves.size(), level_num])

# === PLAYER SPAWNING ===
func _spawn_player(lives: int) -> void:
	var player_scene_path = "res://Ships/Player_%s.tscn" % GameManager.player_manager.selected_ship_id
	if ResourceLoader.exists(player_scene_path):
		player_scene = load(player_scene_path)
	else:
		# Fallback to default player scene
		push_warning("Player scene not found: %s, using default Player_Ship1.tscn" % player_scene_path)
	
	var player_instance = player_scene.instantiate()
	player_instance.global_position = GameManager.player_manager.player_spawn_position
	call_deferred("add_child", player_instance)
	player_instance.call_deferred("set_lives", lives)
	has_spawned_player = true
	if GameManager.debug_mode:
		print("Level.gd: Spawned player with ship_id: %s with %d lives" % [GameManager.player_manager.selected_ship_id, lives])
	
func _check_and_spawn_player() -> void:
	if not has_spawned_player and not get_tree().get_nodes_in_group("Player"):
		await get_tree().create_timer(0.5).timeout
		if GameManager.level_manager.get_current_level() == level_num and not has_spawned_player:
			_spawn_player(GameManager.player_lives)
			call_deferred("_start_campaign_tutorial")
func _start_campaign_tutorial() -> void:
	if level_num == 0:
		TutorialManager.start_level_zero()
	elif level_num == 1:
		TutorialManager.start_level_one()
	elif level_num == 6:
		TutorialManager.start_shadow_level_six()

func _on_level_loaded(_level_num: int) -> void:
	if GameManager.debug_mode:
		print("Level.gd: Received level_loaded signal for level %d" % _level_num)
	# Hide banner ad when level is loaded
	if GameManager.ad_manager and GameManager.ad_manager.is_initialized:
		GameManager.ad_manager.hide_banner_ad()
	# Guard against double spawn — _check_and_spawn_player may have already spawned
	if not has_spawned_player:
		_spawn_player(GameManager.player_lives)

# === PAUSE TOGGLE & TWEEN ===
func _toggle_pause_menu():
	if has_completed_level:
		DebugFlags.debug_print("level completed")
		return
	if get_tree().paused:
		get_tree().paused = false
		GameManager.is_paused = false
		_hide_pause_menu()
	else:
		get_tree().paused = true
		GameManager.is_paused = true
		_show_pause_menu()

func _show_pause_menu():
	pause_menu.visible = true
	animation_player.play("fade_in")

func _hide_pause_menu():
	if not is_inside_tree() or not pause_menu:
		return
		
	var tween = create_tween()
	if tween:
		tween.tween_property(pause_menu, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await tween.finished
		if pause_menu:  # Check again after await
			pause_menu.visible = false

func _on_pause_pressed():
	_toggle_pause_menu()

func _on_game_paused(paused: bool):
	if level_game_over or has_completed_level:
		_hide_pause_menu()
		get_tree().paused = false
		GameManager.is_paused = false
	else:
		get_tree().paused = paused
		GameManager.is_paused = paused
		if paused:
			_show_pause_menu()
		else:
			_hide_pause_menu()

# === GAME OVER ===
func _game_over_triggered():
	if GameManager.level_manager.is_level_just_completed:
		return
	level_game_over = true
	GameManager.request_game_over("Level._game_over_triggered")
	# Set the game over screen active flag in LevelManager
	if GameManager.level_manager:
		GameManager.level_manager.is_game_over_screen_active = true
	get_tree().paused = false
	pause_menu.hide()
	if hud and hud.has_method("update_charge_display"):
		saved_shadow_charge = hud.current_charge if hud.current_charge is float else 0.0
	game_over_screen._on_score_updated(GameManager.score)
	game_over_screen.modulate.a = 0.0
	game_over_screen.show()
	
	# Don't show banner ad when game over screen is displayed
	# Banner ads are hidden when game over screen appears
	
	if is_inside_tree() and game_over_screen:
		var tween = create_tween()
		if tween:
			tween.tween_property(game_over_screen, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# === REVIVE ===
func _on_player_revived():
	# Allow revive when either a revive is pending or the game-over UI is active.
	if not GameManager.is_revive_pending and not GameManager.game_over:
		return
	# Reviving from the game-over flow always grants exactly one life.
	var revive_lives: int = 1
	level_game_over = false
	GameManager.request_game_over_clear("Level._on_player_revived")
	# Reset the game over screen active flag in LevelManager
	if GameManager.level_manager:
		GameManager.level_manager.is_game_over_screen_active = false

	if hud and hud.has_method("update_charge_display"):
		hud.current_charge = saved_shadow_charge
		hud.update_charge_display()
	_clear_enemy_bullets()

	AudioManager.mute_bus("Bullet", false)
	AudioManager.mute_bus("Explosion", false)
	# Use PlayerManager as the single revive entrypoint (handles existing player vs respawn).
	GameManager.revive_player(revive_lives)
	
	# Ensure banner ad is hidden after revive
	if GameManager.ad_manager and GameManager.ad_manager.is_initialized:
		GameManager.ad_manager.hide_banner_ad()

func _clear_enemy_bullets() -> void:
	var bullets_by_id: Dictionary = {}
	for node in get_tree().get_nodes_in_group("EnemyBullet"):
		if node and is_instance_valid(node):
			bullets_by_id[node.get_instance_id()] = node
	for node in get_tree().get_nodes_in_group("enemy_bullet"):
		if node and is_instance_valid(node):
			bullets_by_id[node.get_instance_id()] = node
	for bullet in bullets_by_id.values():
		if bullet and is_instance_valid(bullet):
			bullet.call_deferred("queue_free")

func revive_player():
	_on_player_revived()

# === LEVEL COMPLETE ===
func _on_level_completed(_level_num: int):
	AudioManager.mute_bus("Bullet", true)
	emit_signal("Victory_pose")
	
	# Wait for player victory pose animation to complete before showing level completed UI
	var player = get_tree().get_first_node_in_group("Player")
	if player and player.has_signal("victory_pose_done"):
		await player.victory_pose_done
		# Player may have been freed (game over) during the await.
		if not is_inside_tree():
			return

# === WAVE CLEARED ===
func _on_wave_manager_all_waves_cleared():
	if not has_completed_level:
		has_completed_level = true
		if hud and hud.has_method("reset_charge"):
			hud.reset_charge()
		if wave_manager.all_waves_cleared.is_connected(_on_wave_manager_all_waves_cleared):
			wave_manager.all_waves_cleared.disconnect(_on_wave_manager_all_waves_cleared)
		
		# Check if the last wave was a boss wave
		var is_boss_wave = false
		if wave_manager and wave_manager.current_wave_config and wave_manager.current_wave_config.is_boss_wave():
			is_boss_wave = true
		
		# For level 5 and other boss levels, we want to show the boss clear screen
		var current_level_num = GameManager.level_manager.get_current_level()
		if current_level_num % 5 == 0 and current_level_num > 0:  # All boss levels (5, 10, 15, 20, etc.)
			is_boss_wave = true
		
		if is_boss_wave:
			DebugFlags.debug_print("Level.gd: Boss wave cleared, checking if first time completion")
			# Check if this is the first time completing this boss level
			var boss_levels_completed = GameManager.save_manager.boss_levels_completed
			var is_first_time = not boss_levels_completed.has(current_level_num)
			
			if is_first_time:
				DebugFlags.debug_print("Level.gd: First time boss completion, showing boss clear UI")
				_show_boss_clear_ui()
			else:
				DebugFlags.debug_print("Level.gd: Boss already completed before, showing normal level completed UI")
				_show_level_completed_ui()
		else:
			DebugFlags.debug_print("Level.gd: Non-boss wave cleared, completing level through LevelManager")
			# Call LevelManager.complete_level instead of emitting signal directly
			if current_level_num == 0 and TutorialManager.complete_level_zero():
				return
			if current_level_num == 1 and TutorialManager.complete_level_one():
				return
			GameManager.level_manager.complete_level(current_level_num)

# === BOSS DEFEATED ===
func _on_boss_defeated() -> void:
	if not GameManager.is_revive_pending:
		GameManager.score += 1000
		var current_level: int = GameManager.level_manager.get_current_level()
		
		# Check if this is the first time completing this boss level
		var boss_levels_completed = GameManager.save_manager.boss_levels_completed
		var is_first_time = not boss_levels_completed.has(current_level)
		
		if is_first_time:
			# Show boss clear screen for first time completion
			_show_boss_clear_ui()
		else:
			# For subsequent completions, show normal level completed screen
			_show_level_completed_ui()
	else:
		DebugFlags.debug_print("Level.gd: Revive pending, ignoring boss defeat")

func _show_boss_clear_ui():
	get_tree().paused = false
	pause_menu.hide()
	if boss_clear:
		boss_clear.show()
		if boss_clear.has_method("initialize"):
			boss_clear.initialize()
		# Level knows its own number authoritatively via the exported level_num.
		# BossClear._ready runs during scene instantiation, potentially before
		# this level is the current scene, so its GameManager-derived level can
		# be stale (0). Stamp the correct value after initialize; show_boss_clear
		# refreshes from GameManager first and keeps this fallback otherwise.
		if "current_level" in boss_clear and level_num > 0:
			boss_clear.current_level = level_num
		if boss_clear.has_method("show_boss_clear"):
			boss_clear.show_boss_clear()
	else:
		_show_level_completed_ui()

func _show_level_completed_ui():
	get_tree().paused = false
	pause_menu.hide()
	level_completed.show()
	if level_completed.has_method("initialize"):
		level_completed.initialize()
		
	# Apply any rewards for subsequent boss level completions
	var current_level_num = GameManager.level_manager.get_current_level()
	var boss_levels_completed = GameManager.save_manager.boss_levels_completed
	var is_boss_level = current_level_num % 5 == 0 and current_level_num > 0
	var is_first_time = not boss_levels_completed.has(current_level_num)
	
	if is_boss_level and not is_first_time:
		# For subsequent boss level completions, we still want to give the player some rewards
		# Calculate level completion rewards
		var level_completion_rewards = _calculate_level_completion_rewards(current_level_num)
		var collected_coins = level_completion_rewards.coins
		var collected_crystals = level_completion_rewards.crystals
		
		# Add the rewards to the player's currency
		GameManager.add_currency("coins", collected_coins)
		GameManager.add_currency("crystals", collected_crystals)
		
		# Save progress
		if GameManager.save_manager.autosave_progress:
			GameManager.save_manager.save_progress()
		
		# Play reward sound effect
		if AudioManager:
			var sound_stream: AudioStream = preload("res://Assets/Music/794489__gobbe57__coin-pickup.wav")
			if sound_stream:
				AudioManager.play_sound_effect(sound_stream, "Master")
	
	if is_inside_tree() and level_completed:
		var tween = create_tween()
		if tween:
			tween.tween_property(level_completed, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	GameManager.save_manager.save_progress()

# Add this new function to calculate level completion rewards
func _calculate_level_completion_rewards(level_num_param: int) -> Dictionary:
	return GameManager.calculate_level_completion_rewards(level_num_param)

# === SHADOW MODE ===
func _on_shadow_mode_activated():
	wave_manager._on_shadow_mode_activated()

func _on_shadow_mode_deactivated():
	wave_manager._on_shadow_mode_deactivated()

# === WAVE DETAILS UI ===
func _on_wave_started(current_wave: int, total_waves_count: int) -> void:
	"""Show wave details UI when a new wave starts"""
	if GameManager.debug_mode:
		print("Level: Wave started - %d/%d" % [current_wave, total_waves_count])
	
	_show_wave_details(current_wave, total_waves_count)

func _show_wave_details(current_wave: int, total_waves_count: int) -> void:
	"""Display wave details with fade-in animation and auto-hide after duration"""
	if not wave_details or not level_label or not total_waves_label:
		if GameManager.debug_mode:
			print("Level: Wave details UI nodes not found")
		return
	
	# Kill any existing tween
	if wave_details_tween and wave_details_tween.is_valid():
		wave_details_tween.kill()
	
	# Update labels with wave info
	level_label.text = "Level %d" % [level_num]
	total_waves_label.text = "%d/%d" % [current_wave, total_waves_count]
	
	# Show and animate
	wave_details.visible = true
	wave_details_container.modulate.a = 0.0
	
	# Create animation tween
	wave_details_tween = create_tween()
	wave_details_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # Continue during pause
	
	# Fade in
	wave_details_tween.tween_property(wave_details_container, "modulate:a", 1.0, WAVE_DETAILS_FADE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Wait
	wave_details_tween.tween_interval(WAVE_DETAILS_DISPLAY_DURATION)
	
	# Fade out
	wave_details_tween.tween_property(wave_details_container, "modulate:a", 0.0, WAVE_DETAILS_FADE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Hide after fade out
	wave_details_tween.tween_callback(_hide_wave_details_instant)

func _hide_wave_details_instant() -> void:
	"""Instantly hide wave details UI"""
	if wave_details:
		wave_details.visible = false
	if wave_details_container:
		wave_details_container.modulate.a = 0.0

func handle_node_added(node: Node) -> void:
	# Connect to LevelManager's boss_defeated signal for all boss waves.
	# LevelManager emits this for both direct boss nodes and WaveManager-spawned bosses.
	if node is WaveManager:
		if not GameManager.level_manager.boss_defeated.is_connected(_on_level_manager_boss_defeated):
			GameManager.level_manager.boss_defeated.connect(_on_level_manager_boss_defeated)

func _on_level_manager_boss_defeated() -> void:
	# This is called when a boss is defeated through LevelManager
	# Show the appropriate screen based on whether it's the first time completing this boss level
	var current_level: int = GameManager.level_manager.get_current_level()
	var boss_levels_completed = GameManager.save_manager.boss_levels_completed
	var is_first_time = not boss_levels_completed.has(current_level)
	
	if is_first_time:
		# Show boss clear screen for first time completion
		_show_boss_clear_ui()
	else:
		# For subsequent completions, show normal level completed screen
		_show_level_completed_ui()

func _input(event):
	# Debug-only input: the dev_win action must not do anything in a release
	# build, even though the input action itself still exists in project.godot.
	if not DebugFlags.enabled:
		return
	if GameManager.debug_mode and event.is_action_pressed("debug_next_level"):
		_unlock_next_level_debug()
	if event.is_action_pressed("dev_win"):
		_dev_win()

func _unlock_next_level_debug():
	if GameManager.debug_mode:
		print("Debug: Unlocking next level")
	var current_level = GameManager.level_manager.get_current_level()
	GameManager.level_manager.unlock_next_level(current_level)

func _dev_win():
	GameManager.dev_win()
