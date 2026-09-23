extends Control

# Import formation_enums to access shared enums
const FormationEnums = preload("res://EnemyManager/Scripts/formation_enums.gd")

@onready var easy_button: TextureButton = $Panel/VBoxContainer/Difficulty_buttons/Control/Easy
@onready var medium_button: TextureButton = $Panel/VBoxContainer/Difficulty_buttons/Control/Medium
@onready var hard_button: TextureButton = $Panel/VBoxContainer/Difficulty_buttons/Control/Hard
@onready var back_button: TextureButton = $Panel/VBoxContainer/Menu_buttons/Back
@onready var start_button: TextureButton = $Panel/VBoxContainer/Menu_buttons/Start
@onready var description_label: RichTextLabel = $Panel/DescriptionLabel

const NORMAL_UNLOCK_LEVEL: int = 10
const HARD_UNLOCK_LEVEL: int = 20

var selected_difficulty: FormationEnums.DifficultyLevel = FormationEnums.DifficultyLevel.EASY
var target_level: int = 1

func _ready():
	# Connect button signals only if not already connected
	if easy_button:
		if not easy_button.pressed.is_connected(_on_easy_pressed):
			easy_button.pressed.connect(_on_easy_pressed)
			
	if medium_button:
		if not medium_button.pressed.is_connected(_on_normal_pressed):
			medium_button.pressed.connect(_on_normal_pressed)

	if hard_button:
		if not hard_button.pressed.is_connected(_on_hard_pressed):
			hard_button.pressed.connect(_on_hard_pressed)

	if back_button:
		if not back_button.pressed.is_connected(_on_back_pressed):
			back_button.pressed.connect(_on_back_pressed)

	if start_button:
		if not start_button.pressed.is_connected(_on_start_pressed):
			start_button.pressed.connect(_on_start_pressed)

	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)

	_refresh_difficulty_locks()
	_update_description(FormationEnums.DifficultyLevel.EASY)
	
func set_target_level(level_num: int) -> void:
	target_level = level_num
	_refresh_difficulty_locks()
	_ensure_valid_selected_difficulty()


func _update_description(difficulty: FormationEnums.DifficultyLevel) -> void:
	selected_difficulty = difficulty
	
	var descriptions = {
		FormationEnums.DifficultyLevel.EASY: "[color=green]Enemies have reduced health, damage, and speed.[/color]",
		(FormationEnums.DifficultyLevel.NORMAL): "[color=yellow]Ships with atleast [b][color=red]ONE[/color][/b] ascension are recommended[/color]",
		FormationEnums.DifficultyLevel.HARD: "[color=orange]Enemies are tough.\nShips with [b][color=red]max[/color][/b] ascension are recommended.[/color]",
		FormationEnums.DifficultyLevel.NIGHTMARE: "[color=red]Ships with max ascensions are required to beat enemies.[/color]",
	}
	
	# Update description label
	description_label.text = descriptions.get(difficulty, "Select a difficulty level")

func _on_easy_pressed() -> void:
	_update_description(FormationEnums.DifficultyLevel.EASY)

func _on_normal_pressed() -> void:
	if not _is_difficulty_unlocked(FormationEnums.DifficultyLevel.NORMAL):
		_show_unlock_requirement(FormationEnums.DifficultyLevel.NORMAL)
		return
	_update_description(FormationEnums.DifficultyLevel.NORMAL)

func _on_hard_pressed() -> void:
	if not _is_difficulty_unlocked(FormationEnums.DifficultyLevel.HARD):
		_show_unlock_requirement(FormationEnums.DifficultyLevel.HARD)
		return
	_update_description(FormationEnums.DifficultyLevel.HARD)

func _on_back_pressed() -> void:
	# Backing out of the picker returns to the map without starting the level;
	# hand the campaign back to level1_entry so map gates keep working.
	TutorialManager.notify_difficulty_cancelled()
	hide()

func _on_start_pressed() -> void:
	if not _is_difficulty_unlocked(selected_difficulty):
		_show_unlock_requirement(selected_difficulty)
		return

	# Get the LevelSelectionManager instance
	var level_selection_manager = get_node("/root/LevelSelectionManager")
	if not level_selection_manager:
		push_error("LevelSelectionManager not available")
		hide()
		return
	
	# Store the selected difficulty globally
	level_selection_manager.set_selected_difficulty(selected_difficulty)
	if GameManager:
		GameManager.set_current_difficulty(selected_difficulty)
	
	# Load enemy data from JSON file based on difficulty
	if level_selection_manager.load_enemy_data_for_difficulty():
		if GameManager.debug_mode:
			print("Difficulty selection: Enemy data loaded successfully")
		
		# Emit signal that difficulty selection is complete
		level_selection_manager.difficulty_selection_complete.emit()
		
		# Load the level with the selected difficulty and enemy data
		if level_selection_manager.selected_level_path != "":
			var level_path: String = level_selection_manager.selected_level_path
			var preloaded_level: PackedScene = null
			if level_selection_manager.has_method("get_preloaded_level"):
				preloaded_level = level_selection_manager.get_preloaded_level(level_path)
			if preloaded_level:
				get_tree().change_scene_to_packed(preloaded_level)
			else:
				get_tree().change_scene_to_file(level_path)
		else:
			if GameManager.debug_mode:
				print("Error: No level path selected")
			hide()
	else:
		if GameManager.debug_mode:
			print("Error: Failed to load enemy data")
		hide()

func _on_visibility_changed() -> void:
	if visible:
		_refresh_difficulty_locks()
		_ensure_valid_selected_difficulty()

func _refresh_difficulty_locks() -> void:
	if easy_button:
		easy_button.disabled = false
		easy_button.modulate = Color(1, 1, 1, 1)

	var normal_unlocked: bool = _is_difficulty_unlocked(FormationEnums.DifficultyLevel.NORMAL)
	if medium_button:
		medium_button.disabled = not normal_unlocked
		medium_button.modulate = Color(1, 1, 1, 1) if normal_unlocked else Color(0.45, 0.45, 0.45, 1)

	var hard_unlocked: bool = _is_difficulty_unlocked(FormationEnums.DifficultyLevel.HARD)
	if hard_button:
		hard_button.disabled = not hard_unlocked
		hard_button.modulate = Color(1, 1, 1, 1) if hard_unlocked else Color(0.45, 0.45, 0.45, 1)

func _ensure_valid_selected_difficulty() -> void:
	if not _is_difficulty_unlocked(selected_difficulty):
		_update_description(FormationEnums.DifficultyLevel.EASY)
		return
	_update_description(selected_difficulty)

func _is_difficulty_unlocked(difficulty: FormationEnums.DifficultyLevel) -> bool:
	if GameManager and GameManager.is_god_mode_active():
		return true

	match difficulty:
		FormationEnums.DifficultyLevel.EASY:
			# Easy is always unlocked for all levels
			return true
		FormationEnums.DifficultyLevel.NORMAL:
			# Normal is unlocked if:
			# 1. Level 10 Easy is completed (global unlock)
			# AND
			# 2. Target level L Easy is completed (per-level unlock)
			var global_unlock = _is_normal_globally_unlocked()
			var per_level_unlock = _is_level_completed_in_difficulty(target_level, "Easy")
			if GameManager.debug_mode:
				print("DifficultySelection: Normal check - global=%s, level_%d_easy=%s" % [global_unlock, target_level, per_level_unlock])
			return global_unlock and per_level_unlock
		FormationEnums.DifficultyLevel.HARD:
			# Hard is unlocked if:
			# 1. Level 20 Normal is completed (global unlock)
			# AND
			# 2. Target level L Normal is completed (per-level unlock)
			var global_unlock = _is_hard_globally_unlocked()
			var per_level_unlock = _is_level_completed_in_difficulty(target_level, "Normal")
			if GameManager.debug_mode:
				print("DifficultySelection: Hard check - global=%s, level_%d_normal=%s" % [global_unlock, target_level, per_level_unlock])
			return global_unlock and per_level_unlock
		_:
			return false

# Check global unlock status from SaveManager
func _is_normal_globally_unlocked() -> bool:
	if not GameManager or not GameManager.save_manager:
		return false
	return GameManager.save_manager.is_normal_globally_unlocked()

func _is_hard_globally_unlocked() -> bool:
	if not GameManager or not GameManager.save_manager:
		return false
	return GameManager.save_manager.is_hard_globally_unlocked()

# Check if a level is completed in a specific difficulty
func _is_level_completed_in_difficulty(level_num: int, difficulty: String) -> bool:
	if not GameManager or not GameManager.save_manager:
		return false
	return GameManager.save_manager.is_level_completed_in_difficulty(level_num, difficulty)

# Check if Easy tier is fully completed (all levels 1-10)
func _is_easy_tier_completed() -> bool:
	if not GameManager or not GameManager.save_manager:
		return false
	return GameManager.save_manager.easy_tier_completed

# Check if Normal tier is fully completed (all levels 1-20)
func _is_normal_tier_completed() -> bool:
	if not GameManager or not GameManager.save_manager:
		return false
	return GameManager.save_manager.normal_tier_completed

func _is_level_completed(level_num: int) -> bool:
	if not GameManager:
		return false
	return GameManager.is_level_completed(level_num)

func _show_unlock_requirement(difficulty: FormationEnums.DifficultyLevel) -> void:
	match difficulty:
		FormationEnums.DifficultyLevel.NORMAL:
			var global_unlocked = _is_normal_globally_unlocked()
			var level_completed_easy = _is_level_completed_in_difficulty(target_level, "Easy")
			
			if not global_unlocked:
				description_label.text = "[color=orange]Complete Level 10 in Easy to unlock Normal difficulty.[/color]"
			elif not level_completed_easy:
				description_label.text = "[color=orange]Complete Level %d in Easy first.[/color]" % target_level
			else:
				description_label.text = "[color=orange]Complete Level %d in Easy first.[/color]" % target_level
		FormationEnums.DifficultyLevel.HARD:
			var global_unlocked = _is_hard_globally_unlocked()
			var level_completed_normal = _is_level_completed_in_difficulty(target_level, "Normal")
			
			if not global_unlocked:
				description_label.text = "[color=orange]Complete Level 20 in Normal to unlock Hard difficulty.[/color]"
			elif not level_completed_normal:
				description_label.text = "[color=orange]Complete Level %d in Normal first.[/color]" % target_level
			else:
				description_label.text = "[color=orange]Complete Level %d in Normal first.[/color]" % target_level
		_:
			description_label.text = "Select a difficulty level"
