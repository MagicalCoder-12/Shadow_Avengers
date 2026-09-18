extends Control

var pLifeIcon := preload("uid://ceg6sboym3t71")
signal pause_requested

@onready var lifeContainer := $LifeContainer
@onready var timer_label: Label = $time/Timer  
@onready var shadow_mode_button: ShadowModeButton = $ShadowModeButton
@onready var h_box_container: HBoxContainer = $HBoxContainer
@onready var power_symbol: TextureRect = $HBoxContainer/PowerSymbol
@onready var power_symbol_2: TextureRect = $HBoxContainer/PowerSymbol2
@onready var power_symbol_3: TextureRect = $HBoxContainer/PowerSymbol3
@onready var power_symbol_4: TextureRect = $HBoxContainer/PowerSymbol4

@export var charge_per_enemy: float = 10.0
@export var max_charge: float = 100.0
var elapsed_time: float = 0.0

# Track the number of attack boost powerups collected
var attack_boost_count: int = 0

func _get_shadow_mode_duration() -> float:
	if GameManager and GameManager.has_method("get_shadow_mode_duration"):
		return float(GameManager.get_shadow_mode_duration())
	return 3.5

func _ready():
	if not pLifeIcon or not pLifeIcon.can_instantiate():
		push_error("Invalid pLifeIcon preload")
	clear_lives()
	
	# Initialize attack_boost_count from PlayerManager
	if GameManager.player_manager:
		attack_boost_count = GameManager.player_manager.player_stats.get("attack_level", 0)
	
	# Set all power symbols to silhouette initially
	set_all_power_symbols_to_silhouette()
	# Show power symbols based on initial attack level
	update_power_symbols()
	
	# Load HUD settings from ConfigLoader
	_load_hud_settings()
	
	# Connect signals
	GameManager.on_player_life_changed.connect(_on_player_life_changed)
	GameManager.wave_started.connect(_on_wave_started)
	GameManager.all_waves_cleared.connect(_on_all_waves_cleared)
	GameManager.game_paused.connect(_on_game_paused)
	GameManager.shadow_mode_activated.connect(_on_shadow_mode_activated)
	GameManager.shadow_mode_deactivated.connect(_on_shadow_mode_deactivated)
	GameManager.enemy_killed.connect(_on_enemy_killed)
	GameManager.god_mode_changed.connect(_on_god_mode_changed)
	# Connect to player manager for attack boost notifications
	GameManager.ship_stats_updated.connect(_on_ship_stats_updated)
	# Connect to level manager for level loaded notifications
	if GameManager.level_manager:
		GameManager.level_manager.level_loaded.connect(_on_level_loaded)
	if shadow_mode_button:
		shadow_mode_button.set_enabled(false)
		# Connect shadow mode button signal (if not already connected in .tscn)
		if not shadow_mode_button.shadow_mode_requested.is_connected(_on_shadow_mode_requested):
			shadow_mode_button.shadow_mode_requested.connect(_on_shadow_mode_requested)
	# Initialize displays
	_on_player_life_changed(GameManager.player_lives)
	update_button_visibility()
	start_timer()


func _on_level_loaded(_level_num: int):
	"""Called when a new level is loaded"""
	reset_hud_state()

# Set all power symbols to silhouette (grayed out) initially
func set_all_power_symbols_to_silhouette():
	if power_symbol:
		power_symbol.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grayed out
	if power_symbol_2:
		power_symbol_2.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grayed out
	if power_symbol_3:
		power_symbol_3.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grayed out
	if power_symbol_4:
		power_symbol_4.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grayed out

# Update power symbols based on attack boost count
func update_power_symbols():
	# Set all symbols to silhouette first
	set_all_power_symbols_to_silhouette()
	
	# Colorize symbols based on attack boost count
	if power_symbol:
		if attack_boost_count >= 1:
			power_symbol.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Full color
		else:
			power_symbol.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grayed out
	if power_symbol_2:
		if attack_boost_count >= 2:
			power_symbol_2.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Full color
		else:
			power_symbol_2.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grayed out
	if power_symbol_3:
		if attack_boost_count >= 3:
			power_symbol_3.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Full color
		else:
			power_symbol_3.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grayed out
	if power_symbol_4:
		if attack_boost_count >= 4:
			power_symbol_4.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Full color
		else:
			power_symbol_4.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grayed out

func _load_hud_settings() -> void:
	"""Load HUD settings from ConfigLoader"""
	if is_instance_valid(ConfigLoader) and ConfigLoader.hud_settings:
		charge_per_enemy = ConfigLoader.hud_settings.get("charge_per_enemy", 10.0)
		max_charge = ConfigLoader.hud_settings.get("max_charge", 100.0)
	else:
		# Use default values if ConfigLoader is not available
		charge_per_enemy = 10.0
		max_charge = 100.0
	
	# Update shadow mode button settings
	if shadow_mode_button:
		shadow_mode_button.max_charge = max_charge
		shadow_mode_button.charge_per_enemy = charge_per_enemy

func _on_enemy_killed(_enemy: Node) -> void:
	"""Called when an enemy is killed to charge shadow mode"""
	add_enemy_kill_charge()

func _process(delta: float):
	elapsed_time += delta
	update_timer_display()

func start_timer():
	elapsed_time = 0.0

func reset_timer():
	elapsed_time = 0.0

func update_timer_display():
	if not timer_label:
		return
	
	var seconds = elapsed_time
	var minutes = seconds / 60.0
	seconds = fmod(seconds, 60.0)
	
	# Format as MM:SS.mmm
	timer_label.text = "%02d:%05.2f" % [minutes, seconds]

# Clears current life icons
func clear_lives():
	for child in lifeContainer.get_children():
		child.queue_free()

# Set the life icons based on current lives
func set_lives(lives: int):
	clear_lives()
	for i in range(lives):
		var life_icon = pLifeIcon.instantiate()
		if life_icon:
			lifeContainer.add_child(life_icon)
		else:
			push_error("Failed to instantiate pLifeIcon")


# Updates the player life count
func _on_player_life_changed(life: int):
	set_lives(life)

# Updates the display when a new wave starts
func _on_wave_started(_current_wave: int, _total_waves: int):
	pass  # We're not showing wave info anymore

# Called when all waves are cleared
func _on_all_waves_cleared():
	var seconds = elapsed_time
	var minutes = seconds / 60.0
	seconds = fmod(seconds, 60.0)
	timer_label.text = "%02d:%05.2f" % [minutes, seconds]

# Updates the display when the game is paused or resumed
func _on_game_paused(paused: bool):
	if timer_label:
		if paused:
			timer_label.text = "Paused"
		else:
			update_timer_display()

# Called when an enemy is killed to increase charge
func add_enemy_kill_charge(amount: float = charge_per_enemy):
	if GameManager.is_god_mode_active():
		if shadow_mode_button:
			shadow_mode_button.set_charge(shadow_mode_button.max_charge)
		return

	if not GameManager.level_manager.shadow_mode_unlocked:
		return
	if GameManager.level_manager.shadow_mode_enabled:
		return
	if shadow_mode_button:
		shadow_mode_button.add_charge(amount)

# Called when the shadow mode button is pressed
func _on_shadow_mode_requested():
	var shadow_mode_duration: float = _get_shadow_mode_duration()
	if GameManager.is_god_mode_active():
		if shadow_mode_button and shadow_mode_button.is_enabled and not GameManager.level_manager.shadow_mode_enabled:
			GameManager.activate_shadow_mode(shadow_mode_duration)
		return

	if not GameManager.level_manager.shadow_mode_unlocked:
		return
	if shadow_mode_button and shadow_mode_button.is_ready and not GameManager.level_manager.shadow_mode_enabled:
		GameManager.activate_shadow_mode(shadow_mode_duration)

# Updates button visibility
func update_button_visibility():
	var should_be_visible: bool = GameManager.is_god_mode_active() or GameManager.level_manager.shadow_mode_unlocked
	if shadow_mode_button:
		shadow_mode_button.set_enabled(should_be_visible)
		if GameManager.is_god_mode_active():
			shadow_mode_button.set_charge(shadow_mode_button.max_charge)

# Reset HUD state for new level
func reset_hud_state():
	attack_boost_count = 0
	update_power_symbols()  # This will set symbols to silhouette based on attack_boost_count (0)
	reset_charge()
	update_button_visibility()
	start_timer()
	_on_player_life_changed(GameManager.player_lives)

# Resets shadow mode charge
func reset_charge():
	if shadow_mode_button:
		if GameManager.is_god_mode_active():
			shadow_mode_button.set_charge(shadow_mode_button.max_charge)
		else:
			shadow_mode_button.reset_charge()

# Handle shadow mode activation
func _on_shadow_mode_activated():
	if shadow_mode_button:
		shadow_mode_button.reset_charge()

# Handle shadow mode deactivation
func _on_shadow_mode_deactivated():
	if GameManager.is_god_mode_active() and shadow_mode_button:
		shadow_mode_button.set_charge(shadow_mode_button.max_charge)
	update_button_visibility()

func _on_god_mode_changed(_enabled: bool) -> void:
	update_button_visibility()
	reset_charge()

# Update power symbols when ship stats change
@warning_ignore("unused_parameter")
func _on_ship_stats_updated(ship_id: String, new_damage: int):
	"""Called when ship stats are updated, which happens when collecting attack boost powerups"""
	# Get the current attack level from PlayerManager
	var current_attack_level = GameManager.player_manager.player_stats.get("attack_level", 0)
	
	# Update attack boost count if it has changed
	if current_attack_level != attack_boost_count:
		attack_boost_count = current_attack_level
		update_power_symbols()
		
		# Ensure count doesn't exceed the number of power symbols we have
		attack_boost_count = min(attack_boost_count, 4)


func _on_pause_button_down() -> void:
	pause_requested.emit()
