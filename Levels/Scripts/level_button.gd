extends TextureButton

@onready var label: Label = $Label

const Level_1 = "res://Levels/level_1.tscn"
@onready var star_bronze: TextureRect = $Stars/Star_bronze
@onready var star_silver: TextureRect = $Stars/Star_silver
@onready var star_gold: TextureRect = $Stars/Star_gold

signal level_selected(level_num: int)

@export var locked: bool = true:
	set(value):
		locked = value
		if locked:
			level_locked()
		else:
			level_unlocked()

var level_num = 1 # Default to 1, will be updated by LevelButtons
var world_num = 1 # Track which world this level belongs to
var level_in_world = 1 # Track level number within the world

func set_level(num: int, levels_per_world: int = 10) -> void:
	level_num = num
	
	# Calculate world and level within world
	@warning_ignore("integer_division")
	world_num = ((num - 1) / levels_per_world) + 1
	level_in_world = ((num - 1) % levels_per_world) + 1
	
	if label:
		label.text = str(world_num) + "-" + str(level_in_world)

func level_locked() -> void:
	level_state(true)

func level_unlocked() -> void:
	level_state(false)

func level_state(value: bool) -> void:
	disabled = value
	if label:
		label.visible = true

func _on_pressed():
	if not locked:
		if not TutorialManager.can_start_level(level_num):
			return
		TutorialManager.notify_level_selected(level_num)
		# Stop the map sound
		var map_scene = get_tree().current_scene
		if map_scene.has_node("map"):
			var map_audio = map_scene.get_node("map")
			if map_audio and map_audio.is_playing():
				map_audio.stop()
		
		# Store the selected level path globally
		var level_path = "res://Levels/level_%d.tscn" % level_num
		var level_selection_manager = get_node("/root/LevelSelectionManager")
		if level_selection_manager:
			level_selection_manager.set_selected_level(level_path)
			if level_selection_manager.has_method("request_level_preload"):
				level_selection_manager.request_level_preload(level_path)
		else:
			push_error("LevelSelectionManager not available")
		
		# Emit signal to notify listeners (like map scene) that level was selected
		level_selected.emit(level_num)
		
		# Show difficulty selection panel without changing scenes
		_show_difficulty_selection()

func _show_difficulty_selection() -> void:
	# Show the existing difficulty selection panel by traversing up the scene tree
	var current_node = self
	
	# Traverse up to find the map node
	while current_node and current_node.name != "Map":
		current_node = current_node.get_parent()
		if not current_node:
			return
	
	# Find the difficulty selection panel
	if current_node.has_node("CanvasLayer/DifficultySelection"):
		var difficulty_panel = current_node.get_node("CanvasLayer/DifficultySelection")

		# Set the target level
		if difficulty_panel.has_method("set_target_level"):
			difficulty_panel.set_target_level(level_num)

		# Show the canvas layer and difficulty selection panel
		if current_node.has_node("CanvasLayer"):
			var canvas_layer = current_node.get_node("CanvasLayer")
			canvas_layer.show()
			canvas_layer.visible = true
		
			difficulty_panel.show()
			difficulty_panel.visible = true
			
			# Bring the panel to the front to ensure it's visible
			if difficulty_panel is Control:
				# Make sure it's at the top of the z-index
				difficulty_panel.z_index = 100
				
				# Ensure the panel is enabled and can receive input
				difficulty_panel.mouse_filter = Control.MOUSE_FILTER_STOP
				difficulty_panel.focus_mode = Control.FOCUS_ALL
				difficulty_panel.grab_focus()
				
				# Make sure the panel is properly positioned in the scene tree
				difficulty_panel.set_process(true)
				difficulty_panel.set_physics_process(true)
		
		# Focus a valid interactive control to avoid focus warnings on non-focusable roots.
		if difficulty_panel.has_method("focus_default_control"):
			difficulty_panel.focus_default_control()
		elif difficulty_panel is Control:
			var panel_control := difficulty_panel as Control
			if panel_control.focus_mode == Control.FOCUS_NONE:
				panel_control.focus_mode = Control.FOCUS_ALL
			panel_control.grab_focus()
