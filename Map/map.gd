extends Control

@onready var level_buttons: Control = $LevelButtons
@onready var canvaslayer: CanvasLayer = $CanvasLayer
@onready var difficulty_selection: Control = $CanvasLayer/DifficultySelection
@onready var difficulty_unlocked: Control = $CanvasLayer/difficultyUnlocked
@onready var harddifficulty_unlocked: Control = $CanvasLayer/harddifficultyUnlocked

const Intern_menu = "res://MainScenes/Intern_Menu.tscn"
const Shop = "res://MainScenes/upgrade_menu.tscn"

# Configuration for world-level format
@export var levels_per_world: int = 10
# Called when the node enters the scene tree
func _ready():
	call_deferred("_start_campaign_tutorial")
	# Hide stars immediately to prevent flickering during transition
	hide_all_stars()
	if difficulty_unlocked:
		difficulty_unlocked.hide()
	if harddifficulty_unlocked:
		harddifficulty_unlocked.hide()
	# Hide difficulty selection panel initially
	if difficulty_selection:
		difficulty_selection.hide()
	
	# Connect to prepare_map_scene signal to update stars before scene transition
	if GameManager.has_signal("prepare_map_scene"):
		GameManager.prepare_map_scene.connect(_on_prepare_map_scene)
	
	# Wait until the scene is fully ready (fixes transition issues)
	call_deferred("_initialize_level_buttons")

	# Show banner ad only on map scene
	if GameManager and GameManager.ad_manager:
		# Add a small delay before showing banner to prevent conflicts
		await get_tree().create_timer(1.0).timeout
		# Check if we're still in the map scene and no ad is showing
		if is_inside_tree() and GameManager.ad_manager.is_initialized and not GameManager.ad_manager.is_ad_showing:
			GameManager.ad_manager.show_banner_ad()

	# Connect to level_unlocked signal to update buttons dynamically
	GameManager.level_unlocked.connect(_on_level_unlocked)

	# Connect to level_star_earned signal to update stars
	GameManager.level_star_earned.connect(_on_level_star_earned)

	get_tree().get_root().connect("go_back_requested", _on_back_pressed)
	
	# Check if difficulty selection should be shown (after level 10 completion)
	_check_and_show_difficulty_unlocked()

# Hide banner ad when leaving the map scene
func _exit_tree() -> void:
	if GameManager and GameManager.ad_manager:
		GameManager.ad_manager.hide_banner_ad()

# Check and show difficulty unlock notification if level 10 is completed
func _check_and_show_difficulty_unlocked():
	# Check if player has completed level 10 and hasn't shown the difficulty unlock yet
	if GameManager and GameManager.save_manager and GameManager.level_manager:
		# Check for normal difficulty unlock (level 10)
		if GameManager.is_level_completed(10) and not GameManager.save_manager.difficulty_unlocked_showed:
			# Show difficulty unlock notification
			_show_difficulty_unlocked()
			# Mark as shown
			GameManager.save_manager.difficulty_unlocked_showed = true
			GameManager.save_progress()
			if GameManager.debug_mode:
				print("Map: Difficulty selection unlocked notification shown")
		
		# Check for hard difficulty unlock (level 20)
		if GameManager.save_manager.is_hard_globally_unlocked() and not GameManager.save_manager.hard_difficulty_unlocked_showed:
			# Show hard difficulty unlock notification
			_show_hard_difficulty_unlocked()
			# Mark as shown
			GameManager.save_manager.hard_difficulty_unlocked_showed = true
			GameManager.save_progress()
			if GameManager.debug_mode:
				print("Map: Hard difficulty selection unlocked notification shown")

# Show difficulty unlock notification
func _show_difficulty_unlocked():
	if difficulty_unlocked:
		difficulty_unlocked.show()
		# Auto-hide after a few seconds
		await get_tree().create_timer(3.0).timeout
		if difficulty_unlocked and is_inside_tree():
			difficulty_unlocked.hide()

# Show hard difficulty unlock notification
func _show_hard_difficulty_unlocked():
	if harddifficulty_unlocked:
		harddifficulty_unlocked.show()
		# Auto-hide after a few seconds
		await get_tree().create_timer(3.0).timeout
		if harddifficulty_unlocked and is_inside_tree():
			harddifficulty_unlocked.hide()

# Hide all stars immediately to prevent flickering during transition
func hide_all_stars():
	var buttons = level_buttons.get_children()
	for i in range(buttons.size()):
		var button = buttons[i]
		
		# Hide all star types
		var star_bronze = _get_star_sprite(button, "Star_bronze")
		var star_silver = _get_star_sprite(button, "Star_silver")
		var star_gold = _get_star_sprite(button, "Star_gold")
		
		if star_bronze:
			star_bronze.hide()
		if star_silver:
			star_silver.hide()
		if star_gold:
			star_gold.hide()
		
		# Also hide fallback star for backward compatibility
		var star = button.get_node_or_null("Star")
		if star:
			star.hide()

# Update stars before scene transition
func _on_prepare_map_scene():
	update_stars()

# Handles all button initialization
func _initialize_level_buttons():
	# Debug check with fallback
	if level_buttons == null:
		level_buttons = get_node_or_null("LevelButtons")
		if level_buttons == null:
			return
	
	# Get all buttons with null check
	var buttons = level_buttons.get_children()
	if buttons.is_empty():
		return
	
	# Initialize each button with full safety checks
	for i in range(buttons.size()):
		var button = buttons[i]
		
		# 1. Ensure button is visible and interactive
		button.show()
		button.set_process(true)
		
		# 2. Set level number with world-level format
		if button.has_method("set_level"):
			button.call("set_level", i + 1, levels_per_world)
		
		# 3. Set locked state based on GameManager
		var is_unlocked = GameManager.is_level_unlocked(i + 1)
		button.locked = not is_unlocked # Set custom locked property
		
		# 4. Connect signals safely
		if button.has_signal("level_selected"):
			# Connect to local handler to show difficulty selection
			if not button.is_connected("level_selected", Callable(self, "_on_level_button_pressed")):
				button.connect(
					"level_selected",
					Callable(self, "_on_level_button_pressed"),
					CONNECT_DEFERRED
				)
		
		# 5. Force position update (fixes rendering glitches)
		button.position = button.position # Triggers transform update
	
	# Final visibility enforcement
	level_buttons.show()
	level_buttons.z_index = 1

	# Hide all stars first to ensure clean state, then update based on completion counts
	hide_all_stars()
	update_stars()

# Update button states when a new level is unlocked
func _on_level_unlocked(_new_level: int):
	update_level_buttons()

# Function to refresh button states
func update_level_buttons():
	var buttons = level_buttons.get_children()
	for i in range(buttons.size()):
		var button = buttons[i]
		var is_unlocked = GameManager.is_level_unlocked(i + 1)
		button.locked = not is_unlocked # Update locked property

# Update stars visibility on level buttons
func update_stars():
	var buttons = level_buttons.get_children()
	for i in range(buttons.size()):
		var button = buttons[i]
		var level_num = i + 1
		
		# Get the star sprites from the button
		var star_bronze: Sprite2D = _get_star_sprite(button, "Star_bronze")
		var star_silver: Sprite2D = _get_star_sprite(button, "Star_silver")
		var star_gold: Sprite2D = _get_star_sprite(button, "Star_gold")
		if star_bronze and star_silver and star_gold:
			
			# Get star level based on highest difficulty completed
			# 0 = none, 1 = Easy (Bronze), 2 = Normal (Silver), 3 = Hard (Gold)
			var star_level = 0
			if GameManager and GameManager.save_manager:
				star_level = GameManager.save_manager.get_level_star(level_num)
			
			# Hide all stars initially
			star_bronze.hide()
			star_silver.hide()
			star_gold.hide()
			
			# Show appropriate star based on highest difficulty completed
			# 1 = Bronze (Easy completed), 2 = Silver (Normal completed), 3 = Gold (Hard completed)
			if star_level >= 1:
				star_bronze.show()
			if star_level >= 2:
				star_bronze.hide()
				star_silver.show()
			if star_level >= 3:
				star_bronze.hide()
				star_silver.hide()
				star_gold.show()
		else:
			# Fallback for backward compatibility - original logic
			var star = button.get_node_or_null("Star")
			if star:
				if GameManager.is_level_completed(i + 1):
					star.show()
				else:
					star.hide()

# Called when a level is completed and a star is earned
func _on_level_star_earned(_level_num: int = 0):
	update_stars()

func _get_star_sprite(button: Node, star_name: String) -> Sprite2D:
	if button == null:
		return null

	# Current level button layout stores stars under the `Stars` child node.
	var nested_path := "Stars/%s" % star_name
	var nested_star := button.get_node_or_null(nested_path)
	if nested_star is Sprite2D:
		return nested_star as Sprite2D

	# Backward-compat fallback for layouts where stars are direct children.
	var direct_star := button.get_node_or_null(star_name)
	if direct_star is Sprite2D:
		return direct_star as Sprite2D

	return null

func _start_campaign_tutorial() -> void:
	TutorialManager.on_map_ready()

func _on_back_pressed() -> void:
	canvaslayer.hide()
	GameManager.change_scene(Intern_menu)

func _on_shop_pressed() -> void:
	if not TutorialManager.can_open_shop():
		return
	TutorialManager.notify_shop_opened()
	canvaslayer.hide()
	GameManager.change_scene(Shop)

# Show difficulty selection panel when a level button is pressed
func _on_level_button_pressed(_level_num: int) -> void:
	# Find and show the difficulty selection panel
	if canvaslayer:
		# Look for the difficulty selection panel in the canvas layer
		if canvaslayer.has_node("DifficultySelection"):
			var difficulty_panel = canvaslayer.get_node("DifficultySelection")
			difficulty_panel.show()
			# Set the target level for the difficulty panel
			if difficulty_panel.has_method("set_target_level"):
				difficulty_panel.set_target_level(_level_num)
				if GameManager.debug_mode:
					print("Map: Set target level to ", _level_num)
		else:
			if GameManager.debug_mode:
				print("Map: DifficultySelection panel not found in canvaslayer")
	else:
		if GameManager.debug_mode:
			print("Map: CanvasLayer not found")
