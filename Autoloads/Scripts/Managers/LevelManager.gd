extends Node

var gm: Node
var unlocked_levels: int = 1
var completed_levels: Array = []
var shadow_mode_unlocked: bool:
	get:
		return gm.shadow_mode_state.shadow_mode_unlocked if gm else false
	set(value):
		if gm:
			gm.set_shadow_mode_unlocked(value, "LevelManager.shadow_mode_unlocked")

var shadow_mode_enabled: bool:
	get:
		return gm.shadow_mode_state.shadow_mode_enabled if gm else false
	set(value):
		if gm:
			gm.set_shadow_mode_enabled(value, "LevelManager.shadow_mode_enabled")

var shadow_mode_tutorial_shown: bool:
	get:
		return gm.shadow_mode_state.shadow_mode_tutorial_shown if gm else false
	set(value):
		if gm:
			gm.set_shadow_mode_tutorial_shown(value, "LevelManager.shadow_mode_tutorial_shown")
var is_level_just_completed: bool = false
var is_game_over_screen_active: bool = false

# Signals
signal level_loaded(level_num: int)
signal boss_defeated

const SHADOW_MODE_TUTORIAL_SCENE: PackedScene = preload("res://MainScenes/ShadowModeTutorial.tscn")
const BACKGROUND_MUSIC: AudioStream = preload("res://Assets/Music/Start.ogg")

func _ready() -> void:
	gm = GameManager


func load_level(level_num: int) -> void:
	if not is_level_unlocked(level_num):
		return
	
	# Reset score and lives for each level (per-level progression)
	gm.reset_for_new_level()
	
	# Reset player stats to default values
	gm.reset_player_stats()
	
	# Always set player lives to 3 for each level
	gm.player_lives = 3
	
	var level_path: String = "res://Levels/level_%d.tscn" % level_num
	
	# Stop background music before loading level scenes to prevent overlap
	if level_path != gm.get_start_scene_path() and level_path != gm.get_map_scene_path():
		AudioManager.stop_background_music()
	
	# Hide banner ad when loading a level
	gm.hide_banner_ad_if_initialized()
	
	gm.change_scene(level_path)
	await gm.get_tree().create_timer(0.5).timeout
	
	# Guard: scene may have changed during the await.
	if not is_inside_tree():
		return
	if gm.get_tree().current_scene:
		update_hud_visibility(level_num)
		
		gm.hide_banner_ad_if_initialized()
		
		level_loaded.emit(level_num)
	else:
		push_error("LevelManager: Failed to load level %d, no current scene" % level_num)

func complete_level(current_level: int) -> void:
	if gm.game_over and not gm.is_ad_revive_pending():
		return
	
	is_level_just_completed = true
	
	if gm.player_lives == 0:
		gm.player_lives = 2
	
	gm.save_progress_if_enabled()
	
	# Handle special level completions
	var should_transition_to_next_level: bool = true
	@warning_ignore("unused_variable")
	var is_boss_level: bool = current_level % 5 == 0 and current_level > 0
	var hard_was_globally_unlocked: bool = false
	if gm and gm.save_manager:
		hard_was_globally_unlocked = gm.save_manager.is_hard_globally_unlocked()
	
	# Increment completion count regardless of whether it's first time
	increment_level_completion_count(current_level)

	# Only add to completed levels if not already completed
	if not completed_levels.has(current_level):
		completed_levels.append(current_level)
		gm.level_star_earned.emit(current_level)
		gm.save_progress_if_enabled()
		
		# Check if level 10 is completed for the first time to unlock difficulty selection
		if current_level == 10:
			_unlock_difficulty_selection()
		
		# Check and update difficulty tier completion
		_check_tier_completion()
	
	# Track difficulty-specific level completion (ALWAYS track, even if level was already completed)
	# This tracks the highest difficulty completed for each level
	_track_difficulty_completion(current_level)
	
	if current_level == 20 and gm and gm.save_manager:
		var hard_is_globally_unlocked: bool = gm.save_manager.is_hard_globally_unlocked()
		if not hard_was_globally_unlocked and hard_is_globally_unlocked:
			_unlock_hard_difficulty_selection()
	
	# For boss levels, emit the level_completed signal to show boss clear screen
	# For non-boss levels, also emit the level_completed signal
	gm.level_completed.emit(current_level)
	
	# Unlock next level (but only if it's the next sequential level)
	var next_level: int = current_level + 1
	if next_level == unlocked_levels + 1:  # Only unlock if it's the next sequential level
		unlocked_levels = next_level
		gm.save_progress_if_enabled()
		gm.level_unlocked.emit(next_level)
	
	if should_transition_to_next_level:
		is_level_just_completed = false

func _unlock_difficulty_selection() -> void:
	# Trigger difficulty unlock notification when level 10 is completed
	# This will show the difficulty_unlocked UI on the next map visit
	if gm.save_manager:
		gm.save_manager.difficulty_unlocked_showed = false
		gm.save_progress_if_enabled()


func _unlock_hard_difficulty_selection() -> void:
	# Trigger hard difficulty unlock notification when level 20 is completed
	# This will show the hard_difficulty_unlocked UI on the next map visit
	if gm.save_manager:
		gm.save_manager.hard_difficulty_unlocked_showed = false
		gm.save_progress_if_enabled()


# Track level completion in the specific difficulty
func _track_difficulty_completion(level_num: int) -> void:
	if not gm or not gm.save_manager:
		return
	
	# Get current difficulty from GameManager
	var difficulty = null
	if gm and "current_difficulty" in gm:
		difficulty = gm.current_difficulty
	
	# Try to get difficulty name using the enum directly from GameManager
	var difficulty_name = ""
	if difficulty != null:
		difficulty_name = _get_difficulty_name_from_value(difficulty)
	
	if difficulty_name != "":
		gm.save_manager.mark_level_completed_in_difficulty(level_num, difficulty_name)

# Get difficulty name from enum value
func _get_difficulty_name_from_value(difficulty) -> String:
	# Direct integer comparison (Godot enums are integers internally)
	var diff_int = int(difficulty)
	
	# EASY = 0, NORMAL = 1, HARD = 2
	if diff_int == 0:
		return "Easy"
	elif diff_int == 1:
		return "Normal"
	elif diff_int == 2:
		return "Hard"
	
	# Try string comparison as fallback
	var diff_str = str(difficulty)
	if diff_str.contains("EASY"):
		return "Easy"
	elif diff_str.contains("NORMAL"):
		return "Normal"
	elif diff_str.contains("HARD"):
		return "Hard"
	
	return ""

# Check and update difficulty tier completion status
func _check_tier_completion() -> void:
	if not gm or not gm.save_manager:
		return
	
	# Check Easy tier completion (all levels 1-10 must be completed)
	if not gm.save_manager.easy_tier_completed:
		if _is_easy_tier_completed():
			gm.save_manager.easy_tier_completed = true
			gm.save_progress_if_enabled()
			if gm.debug_mode:
				print("LevelManager: Easy tier fully completed!")
	
	# Check Normal tier completion (all levels 1-20 must be completed)
	if not gm.save_manager.normal_tier_completed:
		if _is_normal_tier_completed():
			gm.save_manager.normal_tier_completed = true
			gm.save_progress_if_enabled()
			if gm.debug_mode:
				print("LevelManager: Normal tier fully completed!")

# Check if Easy tier is fully completed (all levels 1-10)
func _is_easy_tier_completed() -> bool:
	for level in range(1, 11):
		if not completed_levels.has(level):
			return false
	return true

# Check if Normal tier is fully completed (all levels 1-20)
func _is_normal_tier_completed() -> bool:
	for level in range(1, 21):
		if not completed_levels.has(level):
			return false
	return true

func _show_shadow_mode_tutorial() -> void:
	var current_scene = gm.get_tree().current_scene
	if current_scene:
		AudioManager.mute_bus("Bullet", true)
		AudioManager.mute_bus("Explosion", true)
		
		var tutorial_layer = CanvasLayer.new()
		tutorial_layer.name = "ShadowModeTutorialLayer"
		tutorial_layer.layer = 10
		
		var tutorial: Node = SHADOW_MODE_TUTORIAL_SCENE.instantiate()
		tutorial_layer.add_child(tutorial)
		current_scene.add_child(tutorial_layer)
		
		gm.set_shadow_mode_tutorial_shown(true, "LevelManager._show_shadow_mode_tutorial")
		gm.save_progress_if_enabled()
		
		# Properly reset the level completion flag after showing tutorial
		is_level_just_completed = false
	else:
		push_error("LevelManager: Cannot add tutorial: No current scene available")

func unlock_next_level(current_level: int) -> void:
	var next_level: int = current_level + 1
	var next_level_path: String = "res://Levels/level_%d.tscn" % next_level
	if ResourceLoader.exists(next_level_path):
		# Start every level from a clean run state.
		gm.reset_for_new_level()
		# Unlock the next level in the save data
		if next_level > unlocked_levels:
			unlocked_levels = next_level
			gm.save_progress_if_enabled()
		gm.change_scene(next_level_path)
	else:
		gm.change_scene(gm.get_map_scene_path())
	
	is_level_just_completed = false

func unlock_shadow_mode() -> void:
	if not shadow_mode_unlocked:
		gm.set_shadow_mode_unlocked(true, "LevelManager.unlock_shadow_mode")
		gm.save_progress_if_enabled()
		update_hud_visibility()

func activate_shadow_mode(duration: float) -> void:
	if shadow_mode_unlocked:
		gm.request_shadow_mode_activate(duration, "LevelManager.activate_shadow_mode")

func update_hud_visibility(_level_num: int = get_current_level()) -> void:
	var hud: Node = gm.get_tree().current_scene.get_node_or_null("CanvasLayer/HUD")
	if hud and hud.has_node("ShadowModeButton"):
		var shadow_button: ShadowModeButton = hud.get_node("ShadowModeButton") as ShadowModeButton
		if shadow_button:
			var should_be_visible: bool = shadow_mode_unlocked
			shadow_button.visible = should_be_visible
			
			if not should_be_visible:
				shadow_button.set_enabled(false)
				if hud.has_method("reset_charge"):
					hud.reset_charge()

func is_level_unlocked(level: int) -> bool:
	if level == 0:
		return TutorialManager.should_route_to_level_zero()
	if gm and gm.is_god_mode_active():
		return true

	# Progressive level unlock system
	# Level 1: Always unlocked (starting level)
	# Levels 2-10: Unlocked after completing the previous level
	# Levels 11-20: Unlocked after completing the previous level (starting with level 10)
	# Levels 21-30: Unlocked after completing the previous level (starting with level 20)
	
	if level == 1:
		# Starting level - always unlocked
		return true
	elif level <= 10:
		# Easy levels 2-10 - unlocked after completing previous level
		return is_level_completed(level - 1)
	elif level <= 20:
		# Levels 11-20 - unlocked after completing the previous level
		# Level 11 requires level 10, level 12 requires level 11, etc.
		return is_level_completed(level - 1)
	elif level <= 30:
		# Levels 21-30 - unlocked after completing the previous level
		# Level 21 requires level 20, level 22 requires level 21, etc.
		return is_level_completed(level - 1)
	else:
		# Beyond level 30 - use default unlock system
		return level <= unlocked_levels

func is_level_completed(level: int) -> bool:
	return completed_levels.has(level)

# Public function to check if Easy tier is fully completed
func is_easy_tier_completed() -> bool:
	if gm and gm.save_manager:
		return gm.save_manager.easy_tier_completed
	return _is_easy_tier_completed()

# Public function to check if Normal tier is fully completed
func is_normal_tier_completed() -> bool:
	if gm and gm.save_manager:
		return gm.save_manager.normal_tier_completed
	return _is_normal_tier_completed()

# Add functions for level completion count tracking
func get_level_completion_count(level: int) -> int:
	if gm.save_manager:
		return gm.save_manager.get_level_completion_count(level)
	return 0

func increment_level_completion_count(level: int) -> void:
	if gm.save_manager:
		gm.save_manager.increment_level_completion_count(level)
		gm.save_progress_if_enabled()

func get_current_level() -> int:
	var scene_path: String = gm.get_tree().current_scene.scene_file_path if gm.get_tree().current_scene else ""
	var regex = RegEx.new()
	regex.compile("level_(\\d+)\\.tscn")
	var result = regex.search(scene_path)
	if result:
		return int(result.get_string(1))
	return 0

func reset_level_state() -> void:
	gm.request_shadow_mode_deactivate_silent("LevelManager.reset_level_state")
	is_level_just_completed = false
	is_game_over_screen_active = false

func reset_level_progress() -> void:
	unlocked_levels = 1
	gm.set_shadow_mode_unlocked(false, "LevelManager.reset_level_progress")
	gm.set_shadow_mode_tutorial_shown(false, "LevelManager.reset_level_progress")
	completed_levels = []

func handle_node_added(node: Node) -> void:
	if node is WaveManager:
		# Safely connect to WaveManager signals
		if node.has_signal("wave_started") and not node.wave_started.is_connected(_on_wave_started):
			node.wave_started.connect(_on_wave_started)
			
		if node.has_signal("all_waves_cleared") and not node.all_waves_cleared.is_connected(_on_all_waves_cleared):
			node.all_waves_cleared.connect(_on_all_waves_cleared)
	
	if node.is_in_group(gm.GROUP_BOSS):
		if node is Area2D and node.has_signal("boss_defeated"):
			if not node.boss_defeated.is_connected(_on_boss_defeated):
				node.boss_defeated.connect(_on_boss_defeated)

		if node.has_signal("unlock_shadow_mode"):
			if not node.unlock_shadow_mode.is_connected(_on_unlock_shadow_mode):
				node.unlock_shadow_mode.connect(_on_unlock_shadow_mode)

	# Additional safety check for other node types
	if node.has_signal("level_completed"):
		if not node.level_completed.is_connected(_on_level_completed):
			node.level_completed.connect(_on_level_completed)

func _on_level_completed(_level_num: int) -> void:
	# Default implementation - can be overridden
	pass


func _on_wave_started(current_wave: int, total_waves: int) -> void:
	gm.wave_started.emit(current_wave, total_waves)

func _on_all_waves_cleared() -> void:
	gm.all_waves_cleared.emit()

func _on_boss_defeated() -> void:
	# Emit boss_defeated signal for the Level scene to handle.
	# Score is awarded by Level._on_boss_defeated which also handles UI.
	boss_defeated.emit()
	
	# For all levels, complete the level properly through the unified flow
	# But let the Level scene decide which screen to show based on first time completion
	# complete_level(current_level)  # This will be handled by the Level scene

func _on_unlock_shadow_mode() -> void:
	unlock_shadow_mode()
	if not shadow_mode_tutorial_shown:
		_show_shadow_mode_tutorial()

func _exit_tree() -> void:
	# Disconnect any connected signals to prevent memory leaks
	# Note: In autoloads, this is rarely called, but good practice
	pass

