extends Control

# Onready references
@onready var score_label: Label = $PanelContainer/Panel/ScoreContainer/Score
@onready var message_label: Label = $PanelContainer/Panel/Formatter/ButtonsContainer/MessageLabel
@onready var revive_button: Button = $PanelContainer/Panel/Formatter/ButtonsContainer/Revive_container/Revive
@onready var crystal_revive: Button = $PanelContainer/Panel/Formatter/ButtonsContainer/Revive_container/Crystal_revive
@onready var void_shards_display: Label = $Resources/VoidCrystal/Void_Shards_display
@onready var crystals_display: Label = $Resources/Crystal/Crystals_display
@onready var coins_display: Label = $Resources/Money/Coins_display

# Constants
const MAP_SCENE: String = "res://Map/map.tscn"
const SHOP_SCENE: String = "res://MainScenes/upgrade_menu.tscn"
var current_level
var _message_token: int = 0

# Signals
@warning_ignore("unused_signal")
signal player_revived
@warning_ignore("unused_signal")
signal ad_revive_requested

func _ready() -> void:
	# Connect GameManager signals for game state and ads
	if GameManager:
		if not GameManager.game_over_triggered.is_connected(_on_game_over_triggered):
			GameManager.game_over_triggered.connect(_on_game_over_triggered)
			
		if not GameManager.score_updated.is_connected(_on_score_updated):
			GameManager.score_updated.connect(_on_score_updated)
		
		if not GameManager.currency_updated.is_connected(_on_currency_updated):
			GameManager.currency_updated.connect(_on_currency_updated)
			
		if not GameManager.revive_completed.is_connected(_on_revive_completed):
			GameManager.revive_completed.connect(_on_revive_completed)
				
		if GameManager.has_signal("ad_failed_to_load"):
			if not GameManager.ad_failed_to_load.is_connected(_on_ad_failed):
				GameManager.ad_failed_to_load.connect(_on_ad_failed)
				
	else:
		_debug_log("Error: GameManager not found! Game over screen is lost in the void.")
	
	current_level = GameManager.get_current_level() if GameManager else 1
	set_process_input(true)
	revive_button.disabled = false
	crystal_revive.disabled = false
	_on_score_updated(GameManager.score if GameManager else 0)
	_update_resource_display()
	_refresh_revive_buttons()
	_set_default_message()
	get_tree().get_root().connect("go_back_requested", _on_map_pressed)
	_debug_log("GameOverScreen powered up for level %d, ready to revive or restart!" % current_level)
	
	# Make sure the screen is hidden by default
	hide()

func _on_score_updated(value: int) -> void:
	if score_label:
		score_label.text = "Score: %d" % value

func _on_game_over_triggered() -> void:
	# Award half the collected coins and crystals when player dies
	_award_half_collected_currency()
	
	revive_button.disabled = false
	crystal_revive.disabled = false
	visible = true
	_update_resource_display()
	_refresh_revive_buttons()
	_set_default_message()
	_debug_log("Game over triggered, showing screen of doom!")

func _on_currency_updated(_currency_type: String, _new_amount: int) -> void:
	_update_resource_display()

func _format_number(value: int) -> String:
	if value >= 1000000000:
		return "%.1fB" % (value / 1000000000.0)
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return str(value)

func _update_resource_display() -> void:
	if not GameManager:
		return
	if void_shards_display:
		void_shards_display.text = "Void Shards: %s" % _format_number(GameManager.void_shards_count)
	if crystals_display:
		crystals_display.text = "Crystals: %s" % _format_number(GameManager.crystal_count)
	if coins_display:
		coins_display.text = "Coins: %s" % _format_number(GameManager.coin_count)

func _refresh_revive_buttons() -> void:
	if not GameManager:
		return
	
	var ad_remaining: int = GameManager.get_ad_revives_remaining()
	var can_use_ad: bool = GameManager.can_use_ad_revive()
	revive_button.text = "Revive ad" if ad_remaining > 0 else "Ad used"
	revive_button.disabled = not can_use_ad
	
	var crystal_cost: int = GameManager.get_crystal_revive_cost()
	var crystal_remaining: int = GameManager.get_crystal_revives_remaining()
	var can_use_crystal: bool = GameManager.can_use_crystal_revive() and GameManager.can_afford("crystals", crystal_cost)
	if crystal_remaining <= 0:
		crystal_revive.text = "MAX"
	else:
		crystal_revive.text = str(crystal_cost)
	crystal_revive.disabled = not can_use_crystal

func _set_default_message() -> void:
	_message_token += 1
	var ad_status := "Ad revive available" if not revive_button.disabled else "Ad revive unavailable"
	var crystal_status := "Crystal revive cost: %s" % crystal_revive.text if not crystal_revive.disabled else "Crystal revive unavailable"
	message_label.text = "%s | %s" % [ad_status, crystal_status]
	message_label.visible = true

# Award half the collected coins and crystals when player dies
func _award_half_collected_currency() -> void:
	if GameManager:
		# Calculate half of collected coins and crystals (rounded down)
		var half_coins = roundi(GameManager.coins_collected_this_level / 2.0)
		var half_crystals = roundi(GameManager.crystals_collected_this_level / 2.0)


		# Award the half amounts to the player's total
		if half_coins > 0:
			GameManager.add_currency("coins", half_coins)
			_debug_log("Awarded %d coins (half of %d collected)" % [half_coins, GameManager.coins_collected_this_level])
		
		if half_crystals > 0:
			GameManager.add_currency("crystals", half_crystals)
			_debug_log("Awarded %d crystals (half of %d collected)" % [half_crystals, GameManager.crystals_collected_this_level])
		
		# Reset the level currencies since we've awarded them
		GameManager.reset_level_currencies()
		_update_resource_display()

func _on_revive_pressed() -> void:
	if revive_button.disabled or (GameManager and GameManager.is_revive_pending):
		_debug_log("Revive button press ignored: Disabled or revive in progress")
		return
	revive_button.disabled = true
	_show_interaction_message("Requesting ad revive...")
	# Request rewarded ad for revive
	if GameManager:
		if not GameManager.request_ad_revive_from_ui():
			_show_temp_message("Ad revive unavailable right now.")
			_refresh_revive_buttons()
	else:
		emit_signal("ad_revive_requested") # fallback
		_debug_log("Revive button pressed, requesting ad revive! Beam us up, Scotty!")

func _on_ad_failed(ad_type: String, _error_code: Variant) -> void:
	if ad_type != "revive":
		return
	revive_button.disabled = false
	_show_temp_message("Ad failed to load. Try again, space cowboy!")
	_refresh_revive_buttons()
	_debug_log("Ad failed, showing error message and re-enabling revive button")

func _on_revive_completed(success: bool) -> void:
	if success:
		# Use one completion path for ad revives to avoid duplicate revive side effects.
		revive_button.disabled = true
		crystal_revive.disabled = true
		emit_signal("player_revived")
		if GameManager and GameManager.game_over:
			_debug_log("Warning: Game over still true after successful revive! Forcing to false.")
			GameManager.request_game_over_clear("GameOverScreen._on_revive_completed")
		visible = false
		_set_default_message()
		_refresh_revive_buttons()
		_debug_log("Revive completed successfully! Player's back in the galaxy!")
	else:
		revive_button.disabled = false
		_refresh_revive_buttons()
		if message_label.visible:
			_debug_log("Revive failed message already visible from ad failure callback")
			return
		_show_temp_message("Revive failed. Try again or restart, star pilot!")
		_debug_log("Revive failed, showing error message and re-enabling revive button")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if revive_button.disabled or (GameManager and GameManager.is_revive_pending):
			_debug_log("R key press ignored: Revive button disabled or revive pending")
			return
		revive_button.disabled = true
		_show_interaction_message("Requesting ad revive...")
		# Use the same logic as the revive button
		if GameManager:
			if not GameManager.request_ad_revive_from_ui():
				_show_temp_message("Ad revive unavailable right now.")
				_refresh_revive_buttons()
		else:
			emit_signal("ad_revive_requested") # fallback
		_debug_log("R key pressed for revive! Requesting ad like a mad scientist!")

func _on_map_pressed() -> void:
	if GameManager:
		# Leaving a failed run must clear its game-over and player state before another level loads.
		GameManager.reset_game()
		GameManager.change_scene(GameManager.get_map_scene_path())
		_debug_log("Warping to map scene, hyperspace engaged!")
	else:
		_debug_log("Error: GameManager missing, can't warp to map!")

func _on_restart_pressed() -> void:
	if GameManager:
		GameManager.is_paused = false
		GameManager.reset_game()
		var current_level_path = "res://Levels/level_%d.tscn" % current_level
		GameManager.change_scene(current_level_path)
		_debug_log("Restarting level %d, time for a fresh space battle!" % current_level)
	else:
		_debug_log("Error: GameManager missing, can't restart level!")

# Logs debug messages if enabled in Player.gd
func _debug_log(message: String) -> void:
	if GameManager.debug_mode:
		print("[GameOverScreen Debug] " + message)




func _on_crystal_revive_pressed() -> void:
	if crystal_revive.disabled or (GameManager and GameManager.is_revive_pending):
		_debug_log("Crystal revive press ignored: Disabled or revive in progress")
		return
	
	if not GameManager:
		_show_temp_message("GameManager missing. Cannot crystal revive.")
		return
	
	var result: Dictionary = GameManager.try_spend_crystal_revive()
	if not result.get("ok", false):
		var error_message: String = str(result.get("error", "Crystal revive unavailable."))
		if error_message == "Not enough crystals." and result.has("cost"):
			error_message = "Need %d crystals to revive." % int(result["cost"])
		_show_temp_message(error_message)
		_refresh_revive_buttons()
		return
	
	revive_button.disabled = true
	crystal_revive.disabled = true
	_show_interaction_message("Using crystals to revive...")
	emit_signal("player_revived")
	GameManager.request_revive_pending_clear("GameOverScreen._on_crystal_revive_pressed")
	_update_resource_display()
	visible = false
	_set_default_message()
	_debug_log("Crystal revive purchased for %d crystals" % int(result.get("cost", 0)))

func _show_interaction_message(text: String) -> void:
	_message_token += 1
	message_label.text = text
	message_label.visible = true

func _show_temp_message(text: String, duration: float = 3.0) -> void:
	_message_token += 1
	var current_token: int = _message_token
	message_label.text = text
	message_label.visible = true
	await get_tree().create_timer(duration).timeout
	if is_inside_tree() and message_label and current_token == _message_token:
		_set_default_message()
