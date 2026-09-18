extends Control

# Onready references
@onready var scoreLabel := $Panel/VBoxContainer/Score
@onready var void_shard_label: Label = $Panel/VBoxContainer/RewardsContainer/VoidShardsReward/VoidShardLabel
@onready var coin_label: Label = $Panel/VBoxContainer/RewardsContainer/CoinsReward/CoinLabel
@onready var crystal_label: Label = $Panel/VBoxContainer/RewardsContainer/CrystalsReward/CrystalLabel
@onready var total_rewards_label: Label = $Panel/VBoxContainer/TotalRewards

# Constants
const Map = "res://Map/map.tscn"

# Boss clear rewards - these will be calculated based on level
var current_level: int

var signals_connected: bool = false
var screen_shown: bool = false  # Track if the screen has been shown

# Add a method to initialize the screen when it's actually shown
func initialize():
	if not signals_connected:
		# Connect signals from GameManager 
		if GameManager:
			if not GameManager.score_updated.is_connected(set_score):
				GameManager.score_updated.connect(set_score)
				
			current_level = GameManager.get_current_level()
		else:
			push_error("Error: GameManager not found! Boss clear screen is adrift.")
			current_level = 1
		signals_connected = true
	
	set_score(GameManager.score if GameManager else 0)
	
	# Show boss rewards immediately
	_show_boss_rewards()
	
	if GameManager.debug_mode:
		print("[BossClear Debug] Boss clear screen ready for level %d, score: %d" % [current_level, GameManager.score if GameManager else 0])
	
func _ready():
	# Auto-initialize when the node is ready, but only if not already initialized
	if GameManager.debug_mode:
		print("[BossClear Debug] _ready() called")
	if not signals_connected:
		if GameManager.debug_mode:
			print("[BossClear Debug] _ready() called, auto-initializing")
		initialize()
	else:
		if GameManager.debug_mode:
			print("[BossClear Debug] _ready() called, already initialized")

func set_score(value: int) -> void:
	# Update the score label
	if GameManager.debug_mode:
		print("[BossClear Debug] set_score called with value: %d" % value)
	if scoreLabel:
		scoreLabel.text = "Level Score: %d" % value
		if GameManager.debug_mode:
			print("[BossClear Debug] scoreLabel.text set to: %s" % scoreLabel.text)
	else:
		if GameManager.debug_mode:
			print("[BossClear Debug] ERROR: scoreLabel is null!")

func _show_boss_rewards() -> void:
	# Calculate rewards based on level
	var rewards = _calculate_boss_rewards()
	
	# Display the rewards that will be given
	if void_shard_label:
		void_shard_label.text = "Void Shards: +%d" % rewards.void_shards
	if coin_label:
		coin_label.text = "Coins: +%d" % rewards.coins
	if crystal_label:
		crystal_label.text = "Crystals: +%d" % rewards.crystals
	
	if GameManager.debug_mode:
		print("[BossClear Debug] Displaying boss rewards: %d void shards, %d coins, %d crystals" % [rewards.void_shards, rewards.coins, rewards.crystals])

func _calculate_boss_rewards() -> Dictionary:
	if GameManager:
		return GameManager.get_boss_reward_for_level(current_level)
	return {
		"coins": 1000,
		"crystals": 60,
		"void_shards": 50
	}

func _apply_boss_rewards() -> void:
	if GameManager:
		# Calculate rewards
		var rewards = _calculate_boss_rewards()
		
		# Check if this is the first time completing this boss level
		var is_first_time = not GameManager.is_boss_level_completed(current_level)
		
		if is_first_time:
			print("[BossClear Debug] First time completing boss level %d, applying rewards" % current_level)
			# Add the special boss rewards only for first time
			GameManager.add_currency("void_shards", rewards.void_shards)
			GameManager.add_currency("coins", rewards.coins)
			GameManager.add_currency("crystals", rewards.crystals)
			
			# Mark this boss level as completed
			GameManager.mark_boss_level_completed(current_level)
		else:
			print("[BossClear Debug] Boss level %d already completed before")
		
		# Also add any collected coins and crystals from the level (if any)
		var collected_coins = GameManager.coins_collected_this_level if GameManager else 0
		var collected_crystals = GameManager.crystals_collected_this_level if GameManager else 0
		
		if collected_coins > 0:
			GameManager.add_currency("coins", collected_coins)
			if GameManager.debug_mode:
				print("[BossClear Debug] Added %d collected coins from level" % collected_coins)
				
		if collected_crystals > 0:
			GameManager.add_currency("crystals", collected_crystals)
			if GameManager.debug_mode:
				print("[BossClear Debug] Added %d collected crystals from level" % collected_crystals)
		
		# Reset level collected currencies
		if GameManager:
			GameManager.reset_level_currencies()
		
		# Save progress
		GameManager.save_progress_if_enabled()
		
		# Play reward sound effect
		_play_sound_effect("boss_victory")
		
		if GameManager.debug_mode:
			if is_first_time:
				print("[BossClear Debug] Applied boss rewards: %d void shards, %d coins, %d crystals" % [rewards.void_shards, rewards.coins, rewards.crystals])
			else:
				print("[BossClear Debug] No additional boss rewards for previously completed boss level")
			
		# Show total rewards applied message
		if total_rewards_label:
			if is_first_time:
				total_rewards_label.text = "Total Rewards Applied!"
			else:
				total_rewards_label.text = "Boss Already Defeated!"
			total_rewards_label.show()
			if GameManager.debug_mode:
				print("[BossClear Debug] Showing total rewards applied message")
	else:
		if GameManager.debug_mode:
			print("[BossClear Debug] Error: GameManager not found, cannot apply boss rewards")

func _play_sound_effect(sound_type: String) -> void:
	if AudioManager:
		var sound_stream: AudioStream = preload("res://Assets/Music/794489__gobbe57__coin-pickup.wav")
		if sound_stream:
			AudioManager.play_sound_effect(sound_stream, "Master")  # Use Master bus
		else:
			if GameManager.debug_mode:
				print("[BossClear Debug] Warning: Sound stream for %s not found" % sound_type)
	else:
		if GameManager.debug_mode:
			print("[BossClear Debug] Warning: AudioManager not found, cannot play sound effect")

# Add a method to show the boss clear screen
func show_boss_clear():
	if not screen_shown:
		# Apply the boss rewards
		_apply_boss_rewards()
		
		# Make sure the screen is visible
		show()
		screen_shown = true
		# Automatically unlock the next level after a delay if the player doesn't interact
		var auto_unlock_timer = Timer.new()
		auto_unlock_timer.one_shot = true
		auto_unlock_timer.wait_time = 5.0  # 5 seconds delay
		auto_unlock_timer.timeout.connect(_on_auto_unlock_timeout)
		add_child(auto_unlock_timer)
		auto_unlock_timer.start()
		
		if GameManager.debug_mode:
			print("[BossClear Debug] Boss clear screen shown and rewards applied")

		if GameManager.debug_mode:
			print("[BossClear Debug] Boss clear screen shown and rewards applied")

func _on_auto_unlock_timeout():
	# Automatically proceed to the next level if the player hasn't clicked any buttons
	_on_next_pressed()
	
func _on_next_pressed() -> void:
	if GameManager:
		_commit_boss_level_completion_if_needed()
		# Navigate to map
		GameManager.change_scene(GameManager.get_map_scene_path())

func _on_map_pressed() -> void:
	if GameManager:
		_commit_boss_level_completion_if_needed()
		GameManager.change_scene(GameManager.get_map_scene_path())

func _commit_boss_level_completion_if_needed() -> void:
	if not GameManager:
		return
	if not GameManager.is_level_completed(current_level):
		GameManager.complete_level(current_level)

func _on_restart_pressed() -> void:
	if GameManager:
		GameManager.is_paused = false
		GameManager.reset_game()
		var current_level_path = "res://Levels/level_%d.tscn" % current_level
		GameManager.change_scene(current_level_path)
