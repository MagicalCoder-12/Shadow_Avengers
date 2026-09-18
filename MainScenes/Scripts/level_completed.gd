extends Control

@onready var scoreLabel := $Panel/VBoxContainer/Score
@onready var crystalsLabel := $Panel/VBoxContainer/Crystals/Crystals
@onready var coins_label: Label = $Panel/VBoxContainer/Coins/Coins
@onready var completed_sound: AudioStreamPlayer2D = $AudioStreamPlayer2D
@onready var ad_double_button: Button = $Ad_double

const Map = "res://Map/map.tscn"
var current_level: int
var collected_coins: int = 0
var collected_crystals: int = 0
var rewards_doubled: bool = false

var signals_connected: bool = false

# Add a method to initialize the screen when it's actually shown
func initialize():
	if not signals_connected:
		# Connect score signals from GameManager and level completion
		if GameManager:
			if GameManager.debug_mode:
				print("[LevelCompleted Debug] GameManager found, connecting signals")
			
			# Check if signals are already connected before connecting
			if not GameManager.score_updated.is_connected(set_score):
				GameManager.score_updated.connect(set_score)
				if GameManager.debug_mode:
					print("[LevelCompleted Debug] Connected score_updated signal")
			else:
				if GameManager.debug_mode:
					print("[LevelCompleted Debug] score_updated signal already connected")
			
			# Connect level completed signal
			if not GameManager.level_completed.is_connected(_on_level_completed):
				GameManager.level_completed.connect(_on_level_completed)
				if GameManager.debug_mode:
					print("[LevelCompleted Debug] Connected level_completed signal")
			else:
				if GameManager.debug_mode:
					print("[LevelCompleted Debug] level_completed signal already connected")
			
			# Connect ad reward signal
			if not GameManager.ad_reward_granted.is_connected(_on_ad_reward_granted):
				GameManager.ad_reward_granted.connect(_on_ad_reward_granted)
				if GameManager.debug_mode:
					print("[LevelCompleted Debug] Connected ad_reward_granted signal")
			
			current_level = GameManager.get_current_level()
		else:
			push_error("Error: GameManager not found! Level completed screen is adrift.")
			current_level = 1
		signals_connected = true
		
		# Setup ad double button
		if ad_double_button:
			if not ad_double_button.pressed.is_connected(_on_ad_double_pressed):
				ad_double_button.pressed.connect(_on_ad_double_pressed)
				if GameManager.debug_mode:
					print("[LevelCompleted Debug] Connected ad_double_button signal")
			ad_double_button.show()
	
	# Show current values
	if GameManager:
		set_score(GameManager.score)

func _ready():
	# Auto-initialize when the node is ready, but only if not already initialized
	if GameManager.debug_mode:
		print("[LevelCompleted Debug] _ready() called")
	if not signals_connected:
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] _ready() called, auto-initializing")
		initialize()
	else:
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] _ready() called, already initialized")
	
	# Make sure the screen is hidden by default
	hide()

func set_score(value: int) -> void:
	if GameManager.debug_mode:
		print("[LevelCompleted Debug] set_score called with value: %d" % value)
	# Update the score label
	if scoreLabel:
		scoreLabel.text = "Score: %d" % value
	else:
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] scoreLabel is null!")

func set_currency(currency_type: String, value: int) -> void:
	if GameManager.debug_mode:
		print("[LevelCompleted Debug] set_currency called with type: %s, value: %d" % [currency_type, value])
	# Update the currency labels
	if currency_type == "coins":
		if coins_label:
			coins_label.text = "Coins: %d" % value
		else:
			if GameManager.debug_mode:
				print("[LevelCompleted Debug] coins_label is null!")
	elif currency_type == "crystals":
		if crystalsLabel:
			crystalsLabel.text = "Crystals: %d" % value
		else:
			if GameManager.debug_mode:
				print("[LevelCompleted Debug] crystalsLabel is null!")

func _on_level_completed(_level_num: int) -> void:
	if GameManager.debug_mode:
		print("[LevelCompleted Debug] _on_level_completed called with level: %d" % _level_num)
		print("[LevelCompleted Debug] GameManager exists: %s" % (GameManager != null))
		if GameManager:
			print("[LevelCompleted Debug] GameManager.score: %d" % GameManager.score)
			print("[LevelCompleted Debug] GameManager.coins_collected_this_level: %d" % (GameManager.coins_collected_this_level if GameManager else 0))
			print("[LevelCompleted Debug] GameManager.crystals_collected_this_level: %d" % (GameManager.crystals_collected_this_level if GameManager else 0))
	
	# Reset rewards doubled flag
	rewards_doubled = false
	
	# Get the collected coins and crystals for this level
	collected_coins = GameManager.coins_collected_this_level if GameManager else 0
	collected_crystals = GameManager.crystals_collected_this_level if GameManager else 0
	
	# Add level completion rewards based on level difficulty
	var level_completion_rewards = _calculate_level_completion_rewards(_level_num)
	collected_coins += level_completion_rewards.coins
	collected_crystals += level_completion_rewards.crystals
	
	# Show collected coins and crystals for this level
	if coins_label:
		coins_label.text = "Coins: %d" % collected_coins
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Set coins_label text to 'Coins: %d'" % collected_coins)
	else:
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] ERROR: coins_label is null!")
			
	# Show collected crystals for this level
	if crystalsLabel:
		crystalsLabel.text = "Crystals: %d" % collected_crystals
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Set crystalsLabel text to 'Crystals: %d'" % collected_crystals)
	else:
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] ERROR: crystalsLabel is null!")
	
	# Show initial score
	if scoreLabel:
		scoreLabel.text = "Score: %d" % (GameManager.score if GameManager else 0)
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Set scoreLabel text to 'Score: %d'" % (GameManager.score if GameManager else 0))
	else:
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] ERROR: scoreLabel is null!")
	
	# Show ad double button
	if ad_double_button:
		ad_double_button.show()
	
	# Play sound effect when level completed screen is shown
	completed_sound.play()
	# Make sure the screen is visible
	show()
	if GameManager.debug_mode:
		print("[LevelCompleted Debug] Level completed screen shown")
	
	# Reset level currencies since they've been accounted for
	if GameManager:
		GameManager.reset_level_currencies()

func _calculate_level_completion_rewards(level_num: int) -> Dictionary:
	return GameManager.calculate_level_completion_rewards(level_num) if GameManager else {"coins": 200, "crystals": 10}

func _on_next_pressed() -> void:
	if GameManager.debug_mode:
		print("[LevelCompleted Debug] _on_next_pressed called")
	if GameManager:
		# Ensure completion is committed exactly once before leaving the screen.
		_commit_level_completion_if_needed()
		GameManager.score = 0
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Level completed after %d, going to map!" % current_level)
		# Navigate to map
		GameManager.change_scene(GameManager.get_map_scene_path())
	else:
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Error: GameManager missing, can't navigate!")

func _on_map_pressed() -> void:
	if GameManager.debug_mode:
		print("[LevelCompleted Debug] _on_map_pressed called")
	if GameManager:
		# Ensure completion is committed when leaving via Map button as well.
		_commit_level_completion_if_needed()
		GameManager.change_scene(GameManager.get_map_scene_path())
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Warping to map scene, hyperspace engaged!")
	else:
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Error: GameManager missing, can't warp!")

func _commit_level_completion_if_needed() -> void:
	if not GameManager:
		return
	current_level = GameManager.get_current_level()
	if not GameManager.is_level_completed(current_level):
		# Add the collected rewards before completing
		if collected_coins > 0:
			GameManager.add_currency("coins", collected_coins)
			if GameManager.debug_mode:
				print("[LevelCompleted Debug] Added %d coins to total" % collected_coins)
		if collected_crystals > 0:
			GameManager.add_currency("crystals", collected_crystals)
			if GameManager.debug_mode:
				print("[LevelCompleted Debug] Added %d crystals to total" % collected_crystals)
		GameManager.complete_current_level()

func _on_restart_pressed() -> void:
	if GameManager.debug_mode:
		print("[LevelCompleted Debug] _on_restart_pressed called")
	if GameManager:
		GameManager.is_paused = false
		GameManager.reset_game()
		var current_level_path = "res://Levels/level_%d.tscn" % current_level
		GameManager.change_scene(current_level_path)
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Restarting level %d, time for a fresh space battle!" % current_level)
	else:
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Error: GameManager missing, can't restart level!")

func _on_ad_double_pressed() -> void:
	if GameManager.debug_mode:
		print("[LevelCompleted Debug] _on_ad_double_pressed called")
	
	# Check if already doubled
	if rewards_doubled:
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Rewards already doubled, ignoring")
		return
	
	# Check if GameManager and AdManager exist
	if not GameManager or not GameManager.ad_manager:
		push_error("GameManager or AdManager not found!")
		return
	
	# Request a rewarded ad
	if GameManager.debug_mode:
		print("[LevelCompleted Debug] Requesting reward ad for double rewards")
	GameManager.ad_manager.request_reward_ad("level_double")

func _on_ad_reward_granted(reward_type: String) -> void:
	if GameManager.debug_mode:
		print("[LevelCompleted Debug] _on_ad_reward_granted called with type: %s" % reward_type)
	
	# Only process level_double rewards
	if reward_type != "level_double":
		return
	
	# Double the rewards
	if not rewards_doubled:
		rewards_doubled = true
		
		# Double coins
		var doubled_coins = collected_coins * 2
		if coins_label:
			coins_label.text = "Coins: %d (2x!)" % doubled_coins
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Doubled coins: %d -> %d" % [collected_coins, doubled_coins])
		collected_coins = doubled_coins
		
		# Double crystals
		var doubled_crystals = collected_crystals * 2
		if crystalsLabel:
			crystalsLabel.text = "Crystals: %d (2x!)" % doubled_crystals
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Doubled crystals: %d -> %d" % [collected_crystals, doubled_crystals])
		collected_crystals = doubled_crystals
		
		# Hide the ad double button
		if ad_double_button:
			ad_double_button.hide()
		
		if GameManager.debug_mode:
			print("[LevelCompleted Debug] Rewards doubled successfully")
