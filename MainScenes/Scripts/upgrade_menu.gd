extends Control

# ================================
# CONSTANTS & CONFIGURATION
# ================================
const MAP = "res://Map/map.tscn"
const SHOP = "res://MainScenes/Shop.tscn"
const AD_LIMIT_PER_HOUR = 15
const AD_COOLDOWN_SECONDS = 3600  # 1 hour in seconds
const UPGRADE_TRANSACTION_SERVICE_SCRIPT := preload("res://MainScenes/Scripts/Services/UpgradeTransactionService.gd")
const UPGRADE_AD_SERVICE_SCRIPT := preload("res://MainScenes/Scripts/Services/UpgradeAdService.gd")
const UPGRADE_SELECTION_SERVICE_SCRIPT := preload("res://MainScenes/Scripts/Services/UpgradeSelectionService.gd")
const UPGRADE_UI_REFRESH_SERVICE_SCRIPT := preload("res://MainScenes/Scripts/Services/UpgradeUIRefreshService.gd")

# ================================
# UI NODE REFERENCES
# ================================
@onready var Crystals_display: Label = $Resources/Crystal/Crystals_display
@onready var Coins_display: Label = $Resources/Money/Coins_display
@onready var void_shards_display: Label = $Resources/VoidCrystal/Void_Shards_display
@onready var warning: Label = $UI/WarningPanel/Warning_Label
@onready var warning_panel: Panel = $UI/WarningPanel
@onready var selected_ship: TextureRect = $SelectedShipDisplay/HBoxContainer/SelectedShip
@onready var ship_name: Label = $SelectedShipDisplay/HBoxContainer/DetailsContainer/Panel/ShipName
@onready var damage: Label = $SelectedShipDisplay/HBoxContainer/DetailsContainer/Panel/ShipDetails/Stats/Damage
@onready var status_label: Label =$SelectedShipDisplay/HBoxContainer/DetailsContainer/Panel/ShipDetails/Stats/StatusLabel
@onready var ascend: Button = $UI/Buy_Ascend/Ascend
@onready var upgrade_crystals_button: TextureButton = $UI/HBoxContainer/Upgrade_Crystals
@onready var upgrade_coins_button: TextureButton = $UI/HBoxContainer/Upgrade_coins
@onready var buy_button: Button = $UI/Buy_Ascend/Buy
@onready var selected: Button = $UI/Buy_Ascend/Selected
@onready var sat_left_select: Button = $UI/Buy_Ascend/Sat_left_select
@onready var sat_right_select: Button = $UI/Buy_Ascend/Sat_right_select
@onready var power_up: AudioStreamPlayer = $"Power-up"
@onready var msg_panel: Panel = $UI/Msg_panel
@onready var message: Label = $UI/Msg_panel/Message
@onready var details_container: MarginContainer = $SelectedShipDisplay/HBoxContainer/DetailsContainer

@onready var Coins_amt: Label = $UI/HBoxContainer/Upgrade_coins/HBoxContainer/Coins_amt
@onready var Crystal_amt: Label = $UI/HBoxContainer/Upgrade_Crystals/HBoxContainer/Crystal_amt
@onready var Void_Shard: Label = $UI/Buy_Ascend/Ascend/HBoxContainer/Void_Shard

@onready var ship_textures_ui = [
	$UI/ShipContainer/GridContainer/Ship1/S01,
	$UI/ShipContainer/GridContainer/Ship2/S02,
	$UI/ShipContainer/GridContainer/Ship3/S03,
	$UI/ShipContainer/GridContainer/Ship4/S04,
	$UI/ShipContainer/GridContainer/Ship5/S05,
	$UI/ShipContainer/GridContainer/Ship6/S06,
	$UI/ShipContainer/GridContainer/Ship7/S07,
	$UI/ShipContainer/GridContainer/Ship8/S08
]

@onready var satellite_textures_ui = [
	$UI/Satcontainer/GridContainer/sat1/Sat1Texture,
	$UI/Satcontainer/GridContainer/sat2/Sat2Texture,
	$UI/Satcontainer/GridContainer/sat3/Sat3Texture,
	$UI/Satcontainer/GridContainer/sat4/Sat4Texture,
	$UI/Satcontainer/GridContainer/sat5/Sat5Texture,
	$UI/Satcontainer/GridContainer/sat6/Sat6Texture
]

# ================================
# GAME STATE VARIABLES
# ================================
var selected_ship_index: int = 0
var selected_satellite_index: int = 0
var is_satellite_tab_active: bool = false
var is_ad_loading: bool = false
var ad_usage_timer: Timer
var currency_display_updated: bool = false
var refresh_timer: Timer
var details_display_request_id: int = 0
var transaction_service: UpgradeTransactionService = UPGRADE_TRANSACTION_SERVICE_SCRIPT.new()
var ad_service: UpgradeAdService = UPGRADE_AD_SERVICE_SCRIPT.new()
var selection_service: UpgradeSelectionService = UPGRADE_SELECTION_SERVICE_SCRIPT.new()
var ui_refresh_service: UpgradeUIRefreshService = UPGRADE_UI_REFRESH_SERVICE_SCRIPT.new()

# Ship mapping & indexing
var name_to_index = {
	"Ship1/cache": 0,
	"Ship2/cache": 1,
	"Ship3/cache": 2,
	"Ship4/cache": 3,
	"Ship5/cache": 4,
	"Ship6/cache": 5,
	"Ship7/cache": 6,
	"Ship8/cache": 7
}

# ================================
# INITIALIZATION
# ================================
func _ready() -> void:
	call_deferred("_start_campaign_shop_tutorial")
	# Connect to GameManager signals first
	_connect_gamemanager_signals()

	get_tree().get_root().connect("go_back_requested", Callable(self, "_on_back_pressed"))

	# Initialize ad usage tracking
	_initialize_ad_tracking()

	# Initialize refresh timer for currency display
	_initialize_refresh_timer()

	# Check if ships data is available
	if GameManager.ships.is_empty():
		push_warning("No ships data available in GameManager.ships. UI may not initialize correctly.")

	# Initialize UI immediately
	_initialize_ui()
	
	# Set the initial tab state to ships
	is_satellite_tab_active = false
	
	# Add a direct connection as a fallback
	if not GameManager.currency_updated.is_connected(_on_currency_updated):
		GameManager.currency_updated.connect(_on_currency_updated)

	# Connect to visibility notifications
	connect("visibility_changed", _on_visibility_changed)

	# Connect the selected ship's gui_input signal to handle toggle functionality
	if selected_ship and not selected_ship.is_connected("gui_input", _on_selected_ship_gui_input):
		selected_ship.gui_input.connect(_on_selected_ship_gui_input)

func _start_campaign_shop_tutorial() -> void:
	TutorialManager.on_shop_ready(self)

func _connect_gamemanager_signals() -> void:
	"""Connect to relevant GameManager signals"""
	# Connect to ad_reward_granted signal
	if GameManager.has_signal("ad_reward_granted"):
		if not GameManager.ad_reward_granted.is_connected(_on_ad_reward_granted):
			var result = GameManager.ad_reward_granted.connect(_on_ad_reward_granted)
			if result != OK:
				push_error("Failed to connect ad_reward_granted signal, error code: %d" % result)
	else:
		push_error("ad_reward_granted signal not found in GameManager")
	
	# Connect to currency_updated signal with error handling
	if GameManager.has_signal("currency_updated"):
		if not GameManager.currency_updated.is_connected(_on_currency_updated):
			var result = GameManager.currency_updated.connect(_on_currency_updated)
			if result != OK:
				push_error("Failed to connect currency_updated signal, error code: %d" % result)
	else:
		push_error("currency_updated signal not found in GameManager")
	
	# Connect to ad_failed_to_load for reward-ad error handling
	if GameManager.has_signal("ad_failed_to_load"):
		if not GameManager.ad_failed_to_load.is_connected(_on_ad_failed_to_load):
			var failed_result = GameManager.ad_failed_to_load.connect(_on_ad_failed_to_load)
			if failed_result != OK:
				push_error("Failed to connect ad_failed_to_load signal, error code: %d" % failed_result)



func _on_currency_updated(_currency_type: String, _new_amount: int) -> void:
	_update_currency_display()

func _initialize_ui() -> void:
	_update_currency_display()
	currency_display_updated = true
	_update_all_ship_textures()
	_update_all_satellite_textures()

	# Find selected ship index using GameManager's player manager
	if GameManager.player_manager and GameManager.ships.size() > 0:
		for i in range(GameManager.ships.size()):
			if GameManager.ships[i]["id"] == GameManager.player_manager.selected_ship_id:
				selected_ship_index = i
				break

	# Set default tab to ships and show the ship container
	is_satellite_tab_active = false
	var sat_container = get_node("UI/Satcontainer")
	var ship_container = get_node("UI/ShipContainer")
	if sat_container and ship_container:
		sat_container.hide()
		ship_container.show()

	update_ship_ui()
	# Set initial visibility of selection buttons
	_update_selection_buttons_visibility()
	
	# Hide the details container by default
	if details_container:
		details_container.hide()

func _initialize_ad_tracking() -> void:
	ad_usage_timer = Timer.new()
	add_child(ad_usage_timer)
	ad_usage_timer.wait_time = 1.0  # Check every second
	ad_usage_timer.timeout.connect(_on_ad_timer_timeout)
	ad_usage_timer.start()
	ad_service.configure(AD_LIMIT_PER_HOUR, AD_COOLDOWN_SECONDS)
	
	# Load ad usage data from save if available
	_load_ad_usage_data()

func _load_ad_usage_data() -> void:
	ad_service.load_usage(GameManager.save_manager)

func _save_ad_usage_data() -> void:
	# Save ad usage data to SaveManager and call save_progress()
	ad_service.save_usage(GameManager.save_manager)
	
func _on_ad_timer_timeout() -> void:
	ad_service.reset_if_cooldown_elapsed()

func _update_selection_buttons_visibility() -> void:
	# When on satellites tab, hide normal select button and show left/right select buttons
	if is_satellite_tab_active:
		selected.hide()
		if sat_left_select and sat_right_select:
			# Only show left/right select buttons if the currently selected satellite is unlocked
			if not GameManager.satellites.is_empty() and selected_satellite_index < GameManager.satellites.size():
				var current_satellite = GameManager.satellites[selected_satellite_index]
				if current_satellite["unlocked"]:
					sat_left_select.show()
					sat_right_select.show()
				else:
					sat_left_select.hide()
					sat_right_select.hide()
			else:
				# Default to hiding if we can't determine the satellite status
				sat_left_select.hide()
				sat_right_select.hide()
	else:
		# When on ships tab, hide left/right select buttons and only show select for unlocked ships.
		if sat_left_select:
			sat_left_select.hide()
		if sat_right_select:
			sat_right_select.hide()
		if selected:
			var can_show_select := false
			if not GameManager.ships.is_empty() and selected_ship_index >= 0 and selected_ship_index < GameManager.ships.size():
				var current_ship = GameManager.ships[selected_ship_index]
				if current_ship is Dictionary:
					can_show_select = bool(current_ship.get("unlocked", false))
			if can_show_select:
				selected.show()
			else:
				selected.hide()

func _can_show_rewarded_ad() -> bool:
	return ad_service.can_show_rewarded_ad()

func _record_ad_usage() -> void:
	ad_service.record_ad_usage(GameManager.save_manager)

func _show_ad_limit_message() -> void:
	var msg_text = ad_service.get_ad_limit_message()
	_show_warning(msg_text)
	
	# Update the currency display
	_update_currency_display()

func _get_remaining_cooldown_minutes() -> int:
	return ad_service.get_remaining_cooldown_minutes()

# ================================
# CURRENCY MANAGEMENT
# ================================
func _get_current_upgrade_costs() -> Dictionary:
	if GameManager.ships.is_empty() or selected_ship_index >= GameManager.ships.size():
		return {"crystal_cost": 50, "coin_cost": 250, "void_shard_cost": 100}

	var ship = GameManager.ships[selected_ship_index]
	if not ship is Dictionary:
		return {"crystal_cost": 50, "coin_cost": 250, "void_shard_cost": 100}
	return transaction_service.get_ship_upgrade_costs(ConfigLoader, ship)

func _format_number(num: int) -> String:
	return ui_refresh_service.format_number(num)

func _update_currency_display() -> void:
	if not ui_refresh_service:
		return
	ui_refresh_service.update_currency_display(GameManager, Crystals_display, Coins_display, void_shards_display)

func _can_afford_upgrade(cost: int, currency_type: String) -> bool:
	return transaction_service.can_afford(GameManager, cost, currency_type)

func _deduct_currency(amount: int, currency_type: String) -> void:
	transaction_service.deduct_currency(GameManager, amount, currency_type)
	# Ensure the display is updated immediately after deducting currency
	call_deferred("_update_currency_display")

# ================================
# SHIP SELECTION SYSTEM
# ================================
func update_ship_ui() -> void:
	if GameManager.ships.is_empty():
		push_warning("Ships array is empty. Cannot update UI yet.")
		return

	if not selected_ship or not ship_name or not damage:
		push_error("One or more UI elements are null!")
		return

	var ship = GameManager.ships[selected_ship_index]
	var current_texture = _get_ship_texture_dynamic(ship, ship["current_evolution_stage"])
	selected_ship.texture = current_texture

	var current_evolution_name = _get_current_evolution_name(ship["id"], ship["current_evolution_stage"])
	ship_name.text = current_evolution_name
	damage.text = "Damage: %d" % ship["damage"]

	var rank_color = _get_rank_color(ship["rank"])
	ship_name.modulate = rank_color

	if ship["unlocked"]:
		buy_button.hide()
		selected.show()
		var costs = _get_current_upgrade_costs()
		Coins_amt.text = _format_number(costs["coin_cost"])
		Crystal_amt.text = _format_number(costs["crystal_cost"])
		upgrade_coins_button.show()
		upgrade_crystals_button.show()
		selected_ship.modulate = Color.WHITE

		var status_text = ""
		if ship["can_ascend"]:
			status_text = "Ready to Ascend!"
		elif int(ship.get("current_evolution_stage", 0)) >= int(ship.get("max_evolution_stage", 0)):
			var last_threshold = _get_ship_last_threshold(ship)
			var additional_upgrades = max(0, int(ship["upgrade_count"]) - last_threshold)
			if additional_upgrades >= 5:
				status_text = "Max Level"
			else:
				status_text = "Max Ascension Reached! (+%d/5)" % additional_upgrades
		else:
			var next_requirements = _get_next_evolution_requirements(selected_ship_index)
			if next_requirements["can_evolve"]:
				status_text = "Upgrades to next ascension: %d" % next_requirements["upgrades_needed"]
			var upgrade_damage := _get_ship_upgrade_damage_increase(ship)
			if upgrade_damage > 0:
				if status_text.is_empty():
					status_text = "Upgrade: +%d Damage" % upgrade_damage
				else:
					status_text = "%s\nUpgrade: +%d Damage" % [status_text, upgrade_damage]

		status_label.text = status_text
		_update_ascend_button_visibility()
		_update_upgrade_buttons_state()
	else:
		var cost = ship.get("purchase_cost", 0)
		buy_button.show()
		selected.hide()
		upgrade_coins_button.hide()
		upgrade_crystals_button.hide()
		if cost <= 0:
			buy_button.text = "Get Free Ship"
			status_label.text = "Free Ship - Unlock Now!"
		else:
			buy_button.text = "Buy for %d crystals" % cost
			status_label.text = "Locked - Cost: %d crystals" % cost
		selected_ship.modulate = Color.WHITE
		
		# Ensure ascend button is hidden for locked ships
		ascend.visible = false
	
	# Hide the details container by default when updating ship UI
	if details_container:
		details_container.hide()

func update_satellite_ui() -> void:
	if GameManager.satellites.is_empty():
		push_warning("Satellites array is empty. Cannot update UI yet.")
		return

	if not selected_ship or not ship_name or not damage:
		push_error("One or more UI elements are null!")
		return

	var satellite = GameManager.satellites[selected_satellite_index]
	# Load satellite texture using shared refresh service logic
	var satellite_texture = _get_satellite_texture_dynamic(satellite)
	
	if satellite_texture:
		selected_ship.texture = satellite_texture
	else:
		push_warning("Could not load satellite texture for: %s" % satellite.get("display_name", "Unknown"))

	ship_name.text = satellite.get("display_name", "Unknown Satellite")
	damage.text = "Damage: %d" % _get_satellite_total_damage(satellite)

	var rank_color = _get_rank_color(satellite["rank"])
	ship_name.modulate = rank_color

	if satellite["unlocked"]:
		buy_button.hide()
		selected.show()
		var costs = _get_satellite_upgrade_costs()
		Coins_amt.text = _format_number(costs["coin_cost"])
		Crystal_amt.text = _format_number(costs["crystal_cost"])
		upgrade_coins_button.show()
		upgrade_crystals_button.show()
		selected_ship.modulate = Color.WHITE

		var status_text = ""
		if satellite["can_ascend"]:
			status_text = "Ready to Ascend!"
		elif satellite["ascend_count"] >= satellite["max_evolution_stage"]:
			status_text = "Max Level"
		else:
			# Calculate upgrades needed to next ascension
			var thresholds = GameManager.SATELLITE_ASCENSION_THRESHOLDS.get(satellite["id"], [])
			var current_ascend = satellite["ascend_count"]
			if current_ascend < thresholds.size() and satellite["upgrade_count"] < thresholds[current_ascend]:
				var upgrades_needed = thresholds[current_ascend] - satellite["upgrade_count"]
				status_text = "Upgrades to next ascension: %d" % upgrades_needed
			var upgrade_damage := _get_satellite_upgrade_damage_increase(satellite)
			if upgrade_damage > 0:
				if status_text.is_empty():
					status_text = "Upgrade: +%d Damage" % upgrade_damage
				else:
					status_text = "%s\nUpgrade: +%d Damage" % [status_text, upgrade_damage]

		status_label.text = status_text
		_update_satellite_ascend_button_visibility()
		_update_satellite_upgrade_buttons_state()
	else:
		var cost = satellite.get("purchase_cost", 0)
		buy_button.show()
		selected.hide()
		upgrade_coins_button.hide()
		upgrade_crystals_button.hide()
		if cost <= 0:
			buy_button.text = "Get Free Satellite"
			status_label.text = "Free Satellite - Unlock Now!"
		else:
			buy_button.text = "Buy for %d crystals" % cost
			status_label.text = "Locked - Cost: %d crystals" % cost
		selected_ship.modulate = Color.WHITE
		
		# Ensure ascend button is hidden for locked satellites
		ascend.visible = false
	
	# Hide the details container by default when updating satellite UI
	if details_container:
		details_container.hide()
	
	# Update the visibility of selection buttons based on satellite status
	_update_selection_buttons_visibility()

func _update_ascend_button_visibility() -> void:
	var ship = GameManager.ships[selected_ship_index]
	var costs = _get_current_upgrade_costs()
	var current_stage: int = int(ship.get("current_evolution_stage", 0))
	var max_stage: int = int(ship.get("max_evolution_stage", 0))

	# Only show ascend button if ship is unlocked AND can ascend
	if ship["unlocked"] and ship["can_ascend"] and current_stage < max_stage:
		ascend.visible = true
		ascend.disabled = false
		var ship_id = ship["id"]
		var next_stage = min(current_stage + 1, max_stage)
		var next_evolution_name = _get_current_evolution_name(ship_id, next_stage)
		ascend.text = "Ascend to %s" % next_evolution_name
		Void_Shard.text = _format_number(costs["void_shard_cost"])
	else:
		ascend.visible = false

func _update_satellite_ascend_button_visibility() -> void:
	var satellite = GameManager.satellites[selected_satellite_index]
	var costs = _get_satellite_upgrade_costs()

	# Only show ascend button if satellite is unlocked AND can ascend
	if satellite["unlocked"] and satellite["can_ascend"]:
		ascend.visible = true
		ascend.disabled = false
		var next_stage = satellite["ascend_count"] + 1
		var next_evolution_name = _get_current_satellite_evolution_name(satellite["id"], next_stage)
		ascend.text = "Ascend to %s" % next_evolution_name
		Void_Shard.text = _format_number(costs["void_shard_cost"])
	else:
		ascend.visible = false

func _update_upgrade_buttons_state() -> void:
	var ship = GameManager.ships[selected_ship_index]
	var current_stage: int = int(ship.get("current_evolution_stage", 0))
	var max_stage: int = int(ship.get("max_evolution_stage", 0))
	var is_max_level := false
	if current_stage >= max_stage:
		is_max_level = ship["upgrade_count"] >= _get_ship_max_upgrade_cap(ship)

	if ship["can_ascend"] or is_max_level:
		upgrade_crystals_button.disabled = true
		upgrade_crystals_button.modulate = Color.GRAY
		upgrade_coins_button.disabled = true
		upgrade_coins_button.modulate = Color.GRAY
	else:
		upgrade_crystals_button.disabled = false
		upgrade_crystals_button.modulate = Color.WHITE
		upgrade_coins_button.disabled = false
		upgrade_coins_button.modulate = Color.WHITE

func _update_satellite_upgrade_buttons_state() -> void:
	var satellite = GameManager.satellites[selected_satellite_index]
	var is_max_level = satellite["ascend_count"] >= satellite["max_evolution_stage"]

	if satellite["can_ascend"] or is_max_level:
		upgrade_crystals_button.disabled = true
		upgrade_crystals_button.modulate = Color.GRAY
		upgrade_coins_button.disabled = true
		upgrade_coins_button.modulate = Color.GRAY
	else:
		upgrade_crystals_button.disabled = false
		upgrade_crystals_button.modulate = Color.WHITE
		upgrade_coins_button.disabled = false
		upgrade_coins_button.modulate = Color.WHITE

func select_ship_by_name(ship_node_name: String) -> void:
	if name_to_index.has(ship_node_name):
		selected_ship_index = name_to_index[ship_node_name]
		# Only update UI for preview - don't change the actual selected ship yet
		is_satellite_tab_active = false
		update_ship_ui()
	else:
		push_warning("Unknown ship node name: %s" % ship_node_name)

# ================================
# ENHANCED TEXTURE MANAGEMENT
# ================================
func _get_ship_texture_dynamic(ship: Dictionary, evolution_stage: int) -> Texture2D:
	if not ui_refresh_service:
		return null
	return ui_refresh_service.get_ship_texture_dynamic(ship, evolution_stage)


func _get_satellite_texture_dynamic(satellite: Dictionary) -> Texture2D:
	if not ui_refresh_service:
		return null
	return ui_refresh_service.get_satellite_texture_dynamic(satellite)


func _update_all_ship_textures() -> void:
	if not ui_refresh_service:
		return
	ui_refresh_service.update_all_ship_textures(GameManager, ship_textures_ui)

func _update_all_satellite_textures() -> void:
	if not ui_refresh_service:
		return
	ui_refresh_service.update_all_satellite_textures(GameManager, satellite_textures_ui)

func _get_rank_color(rank: String) -> Color:
	match rank:
		"R": return Color.GRAY
		"SR": return Color.YELLOW
		"SSR": return Color.GOLD
		"LR": return Color.CYAN
		_: return Color.WHITE

# ================================
# ENHANCED UPGRADE SYSTEM
# ================================
func _upgrade_ship(ship_index: int, currency_type: String) -> bool:
	var ship = GameManager.ships[ship_index]
	
	# Check if upgrade is possible
	if not _can_upgrade_ship(ship, ship_index):
		return false
	
	var costs = _get_current_upgrade_costs()
	var payment_result := transaction_service.try_pay_upgrade_cost(GameManager, costs, currency_type)
	if not bool(payment_result.get("ok", false)):
		_show_insufficient_funds_message(ship["display_name"], currency_type)
		return false
	
	# Execute the upgrade
	_execute_ship_upgrade(ship, int(payment_result.get("cost", 0)), currency_type, ship_index)
	return true

func _can_upgrade_ship(ship: Dictionary, _ship_index: int) -> bool:
	# Check if ship is unlocked and not ready to ascend
	if not ship["unlocked"] or ship["can_ascend"]:
		return false

	# Check if ship is at max level
	var current_stage: int = int(ship.get("current_evolution_stage", 0))
	var max_stage: int = int(ship.get("max_evolution_stage", 0))
	if current_stage >= max_stage:
		if ship["upgrade_count"] >= _get_ship_max_upgrade_cap(ship):
			return false
	
	return true

func _execute_ship_upgrade(ship: Dictionary, _cost: int, _currency_type: String, ship_index: int) -> void:
	ship["upgrade_count"] += 1
	_apply_stat_boost(ship)
	_update_all_ship_textures()
	_check_ascension_eligibility(ship_index)
	power_up.play()

	if ship_index == selected_ship_index:
		update_ship_ui()
		_show_details_container_temporarily(2.0)

	# Save progress after upgrade
	transaction_service.save_progress(GameManager)

func _show_details_container_temporarily(duration_seconds: float = 2.0) -> void:
	if not details_container:
		return
	details_display_request_id += 1
	var request_id := details_display_request_id
	details_container.show()
	await get_tree().create_timer(duration_seconds).timeout
	if not is_inside_tree():
		return
	if request_id != details_display_request_id:
		return
	if details_container:
		details_container.hide()

func _apply_stat_boost(ship: Dictionary) -> void:
	var damage_increase := _get_ship_upgrade_damage_increase(ship)
	ship["damage"] += damage_increase
	
	# Notify GameManager that ship stats have been updated
	GameManager.notify_ship_stats_updated(ship["id"], ship["damage"])

func _get_ship_upgrade_damage_increase(ship: Dictionary) -> int:
	var base_damage_boost = 5
	var stage_multiplier = 1.0 + (float(ship.get("current_evolution_stage", 0)) * 0.2)
	return int(base_damage_boost * stage_multiplier)

func _check_ascension_eligibility(ship_index: int) -> void:
	var ship = GameManager.ships[ship_index]
	var ship_id = ship["id"]
	var current_stage: int = int(ship.get("current_evolution_stage", 0))
	var max_stage: int = int(ship.get("max_evolution_stage", 0))

	# Final form cannot ascend again even if thresholds data has extra entries.
	if current_stage >= max_stage:
		ship["can_ascend"] = false
		if ship_index == selected_ship_index:
			update_ship_ui()
		return

	var thresholds: Array = _get_ship_thresholds_for_max_stage(ship_id, max_stage)
	if current_stage < thresholds.size() and ship["upgrade_count"] >= int(thresholds[current_stage]):
		ship["can_ascend"] = true
	else:
		ship["can_ascend"] = false

	if ship_index == selected_ship_index:
		update_ship_ui()

func _manual_ascend_ship(ship_index: int) -> bool:
	var ship = GameManager.ships[ship_index]
	var costs = _get_current_upgrade_costs()
	var current_stage: int = int(ship.get("current_evolution_stage", 0))
	var max_stage: int = int(ship.get("max_evolution_stage", 0))

	if not ship["unlocked"] or not ship["can_ascend"] or current_stage >= max_stage:
		return false

	var payment_result := transaction_service.try_pay_ascend_cost(GameManager, costs)
	if not bool(payment_result.get("ok", false)):
		_show_insufficient_funds_message(ship["display_name"], "void_shards")
		return false

	# Increment both counters
	ship["upgrade_count"] += 1
	ship["ascend_count"] += 1

	var ship_id = ship["id"]
	var new_stage = min(current_stage + 1, max_stage)
	ship["current_evolution_stage"] = new_stage
	ship["display_name"] = _get_current_evolution_name(ship_id, new_stage)

	var evolution_bonus = _get_evolution_bonus(ship_id, new_stage)
	ship["damage"] += evolution_bonus["damage"]
	
	# Notify GameManager that ship stats have been updated
	GameManager.notify_ship_stats_updated(ship["id"], ship["damage"])

	if new_stage >= ship["max_evolution_stage"]:
		ship["rank"] = ship["final_rank"]

	ship["can_ascend"] = false
	_update_all_ship_textures()
	power_up.play()
	update_ship_ui()
	_show_evolution_message(ship)

	# Save progress after ascension
	transaction_service.save_progress(GameManager)
	return true

func _get_evolution_bonus(ship_id: String, evolution_stage: int) -> Dictionary:
	var base_bonuses = {"damage": 15}
	var rarity_multiplier = _get_rarity_multiplier(ship_id)
	var stage_multiplier = 1.0 + (evolution_stage * 0.5)

	return {
		"damage": int(base_bonuses["damage"] * rarity_multiplier * stage_multiplier)
	}

func _get_rarity_multiplier(ship_id: String) -> float:
	var ship = _get_ship_by_id(ship_id)
	if not ship:
		return 1.0

	match ship["rank"]:
		"R": return 1.0
		"SR": return 1.3
		"SSR": return 1.6
		"LR": return 2.0
		_: return 1.0

func _get_ship_by_id(ship_id: String) -> Dictionary:
	for ship in GameManager.ships:
		if ship["id"] == ship_id:
			return ship
	return {}

func _show_evolution_message(ship: Dictionary) -> void:
	_show_message("Ship %s has evolved!" % ship["display_name"])

func _show_insufficient_funds_message(shipname: String, currency_type: String) -> void:
	var currency_name = {"crystals": "Crystals", "coins": "Coins", "void_shards": "Void Shards"}.get(currency_type, "Unknown")
	var msg_text = "Not enough %s to upgrade %s!" % [currency_name, shipname]
	_show_warning(msg_text)

# ================================
# OPTIMIZED SIGNAL HANDLERS
# ================================
func _on_ship1_selected(event: InputEvent) -> void:
	_handle_ship_selection(event, "Ship1/cache")

func _on_ship2_selected(event: InputEvent) -> void:
	_handle_ship_selection(event, "Ship2/cache")

func _on_ship3_selected(event: InputEvent) -> void:
	_handle_ship_selection(event, "Ship3/cache")

func _on_ship4_selected(event: InputEvent) -> void:
	_handle_ship_selection(event, "Ship4/cache")

func _on_ship5_selected(event: InputEvent) -> void:
	_handle_ship_selection(event, "Ship5/cache")

func _on_ship6_selected(event: InputEvent) -> void:
	_handle_ship_selection(event, "Ship6/cache")

func _on_ship7_selected(event: InputEvent) -> void:
	_handle_ship_selection(event, "Ship7/cache")

func _on_ship8_selected(event: InputEvent) -> void:
	_handle_ship_selection(event, "Ship8/cache")

func _handle_ship_selection(event: InputEvent, shipname: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select_ship_by_name(shipname)

func _handle_satellite_selection(event: InputEvent, satellite_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select_satellite_by_index(satellite_index)

func select_satellite_by_index(satellite_index: int) -> void:
	if satellite_index < GameManager.satellites.size():
		selected_satellite_index = satellite_index
		# Update UI to show satellite info instead of ship info
		is_satellite_tab_active = true
		update_satellite_ui()
	else:
		push_warning("Invalid satellite index: %d" % satellite_index)

func _on_upgrade_crystals_pressed() -> void:
	if not TutorialManager.can_upgrade_in_shop():
		return
	if _upgrade_selected_item("crystals"):
		if is_satellite_tab_active:
			TutorialManager.notify_satellite_upgraded()
		else:
			TutorialManager.notify_upgrade_completed()
	else:
		_show_upgrade_failed_feedback()

func _on_upgrade_coins_pressed() -> void:
	if not TutorialManager.can_upgrade_in_shop():
		return
	if _upgrade_selected_item("coins"):
		if is_satellite_tab_active:
			TutorialManager.notify_satellite_upgraded()
		else:
			TutorialManager.notify_upgrade_completed()
	else:
		_show_upgrade_failed_feedback()

func _on_ascend_pressed() -> void:
	if not _ascend_selected_item():
		_show_ascend_failed_feedback()

func _show_upgrade_failed_feedback() -> void:
	_show_warning("Upgrade failed")

func _show_ascend_failed_feedback() -> void:
	pass

func _on_ad_reward_granted(ad_type: String) -> void:
	# Update UI when reward is granted through ads
	_update_currency_display()
	_show_ad_reward_message(ad_type)
	is_ad_loading = false
	
	# Record ad usage for crystals and coins
	if ad_type == "crystals" or ad_type == "coins":
		_record_ad_usage()

func _on_ad_failed_to_load(_ad_type: String, _error_data: Variant) -> void:
	# Handle ad failure
	is_ad_loading = false
	# UI can show an error message if needed
	var error_message = "Failed to load ad. Please try again later."
	if _error_data != null and typeof(_error_data) == TYPE_DICTIONARY:
		if _error_data.has("message"):
			error_message = "Ad error: " + str(_error_data["message"])
	
	# Display the error message in the warning panel
	_show_warning(error_message)
	
	# Update the currency display
	_update_currency_display()

func _on_back_pressed() -> void:
	if not TutorialManager.can_exit_shop():
		return
	TutorialManager.notify_shop_exited()
	_save_ship_progress()
	_change_scene_optimized()

func _change_scene_optimized() -> void:
	if power_up and power_up.playing:
		power_up.stop()

	# Use GameManager's scene system
	GameManager.change_scene(MAP)

func _upgrade_selected_item(currency_type: String) -> bool:
	# Determine if we're currently showing a ship or satellite based on active tab
	if is_satellite_tab_active:
		return _upgrade_satellite(selected_satellite_index, currency_type)
	else:
		return _upgrade_ship(selected_ship_index, currency_type)

func _ascend_selected_item() -> bool:
	# Determine if we're currently showing a ship or satellite based on active tab
	if is_satellite_tab_active:
		return _ascend_satellite(selected_satellite_index)
	else:
		return _manual_ascend_ship(selected_ship_index)

func _on_selected_pressed() -> void:
	# Determine if we're currently showing a ship or satellite based on active tab
	if is_satellite_tab_active:
		var satellite = GameManager.satellites[selected_satellite_index]
		var result := selection_service.equip_satellite_both(GameManager, PlayerManager, satellite)
		if bool(result.get("ok", false)):
			PlayerManager.update_selected_satellites()
			_show_message(str(result.get("message", "")))
			TutorialManager.notify_satellite_equipped()
	else:
		var ship = GameManager.ships[selected_ship_index]
		var result := selection_service.select_ship(GameManager, ship)
		if bool(result.get("ok", false)):
			_show_message(str(result.get("message", "")))

func _on_buy_pressed() -> void:
	if is_satellite_tab_active:
		_purchase_satellite(selected_satellite_index)
	else:
		_purchase_ship(selected_ship_index)

# ================================
# AD MANAGEMENT SYSTEM
# ================================
func _on_ad_crystals_pressed() -> void:
	if not is_ad_loading:
		_request_rewarded_ad("crystals")

func _on_ad_coins_pressed() -> void:
	if not is_ad_loading:
		_request_rewarded_ad("coins")

func _request_rewarded_ad(reward_type: String) -> void:
	var result := ad_service.request_reward_ad(GameManager, reward_type)
	if bool(result.get("ok", false)):
		is_ad_loading = true
		return

	is_ad_loading = false
	var error_code := str(result.get("error", ""))
	if error_code == "limit":
		_show_ad_limit_message()
	else:
		var message_text := str(result.get("message", "Ads not available. Please try again later."))
		_show_warning(message_text)
		_update_currency_display()

func _grant_ad_reward(reward_type: String) -> void:
	var message_text := ad_service.grant_reward(GameManager, reward_type)
	_show_message(message_text)
	call_deferred("_update_currency_display")

func _show_ad_reward_message(reward_type: String) -> void:
	var message_text := ad_service.build_reward_message(GameManager, reward_type)
	
	# Display the message in the message panel instead of warning panel
	_show_message(message_text)
	
	# Update the currency display
	_update_currency_display()

# ================================
# SAVE/LOAD SYSTEM
# ================================
func _save_ship_progress() -> void:
	transaction_service.save_progress(GameManager)

# ================================
# UTILITY FUNCTIONS
# ================================
func _get_current_evolution_name(ship_id: String, stage: int) -> String:
	var evolution_names = {}
	if is_instance_valid(ConfigLoader):
		evolution_names = ConfigLoader.upgrade_settings.get("ship_evolution_names", {}).get(ship_id, null)
	else:
		push_warning("ConfigLoader not available. Using default evolution names.")

	# Fallback evolution names (used only when ConfigLoader data is unavailable)
	if not evolution_names:
		var fallback_names = {
			"Ship1": ["NoctiSol", "Solstice", "Eclipse Sovereign"],
			"Ship2": ["Aether Strike", "Void Piercer", "Quantum Saber"],
			"Ship3": ["Astra Blade", "Astra Striker", "Astra Prime"],
			"Ship4": ["Phantom Drake", "Spectral Wyrm", "Ethereal Leviathan", "Void Dragon", "Cosmic Serpent"],
			"Ship5": ["Umbra Wraith", "Shadow Reaper", "Darkness Incarnate", "Void Phantom", "Abyssal Terror", "Nightmare Sovereign", "Obsidian Specter", "Eclipse Revenant", "Nether Shade", "Celestial Wraith"],
			"Ship6": ["Void Howler", "Cosmic Screamer", "Stellar Devourer", "Galactic Destroyer", "Nova Reaver", "Quantum Predator", "Singularity Hunter", "Infinity Ravager"],
			"Ship7": ["Tenebris Fang", "Shadow Blade", "Darkness Cutter", "Void Ripper", "Abyssal Slicer", "Nightmare Edge", "Phantom Cleaver", "Spectral Razor", "Ethereal Scythe"],
			"Ship8": ["Oblivion Viper", "Void Serpent", "Cosmic Cobra", "Stellar Python", "Galactic Anaconda", "Universal Leviathan", "Infinity Wyrm"]
		}
		evolution_names = fallback_names.get(ship_id, null)

	if evolution_names == null:
		return "Unknown"
	return evolution_names[min(stage, evolution_names.size() - 1)]


func _get_current_satellite_evolution_name(satellite_id: String, stage: int) -> String:
	var evolution_names = {}
	if is_instance_valid(ConfigLoader):
		evolution_names = ConfigLoader.upgrade_settings.get("satellite_evolution_names", {}).get(satellite_id, null)
	else:
		push_warning("ConfigLoader not available. Using default satellite evolution names.")

	# Fallback satellite evolution names (used only when ConfigLoader data is unavailable)
	if not evolution_names:
		var fallback_names = {
			"Satellite1": ["Orbital Guardian", "Cosmic Sentinel", "Galactic Warden"],
			"Satellite2": ["Pulsar Companion", "Nebula Satellite", "Stellar Anchor"],
			"Satellite3": ["Quantum Echo", "Phase Satellite", "Dimensional Beacon"],
			"Satellite4": ["Solar Flare", "Corona Satellite", "Helios Guardian"],
			"Satellite5": ["Lunar Shield", "Tidal Satellite", "Moonbeam Sentinel"],
			"Satellite6": ["Astral Link", "Spirit Satellite", "Ethereal Beacon"]
		}
		evolution_names = fallback_names.get(satellite_id, null)

	if evolution_names == null:
		return "Satellite %s" % stage
	return evolution_names[min(stage, evolution_names.size() - 1)]

func _get_ship_thresholds_for_max_stage(ship_id: String, max_stage: int) -> Array:
	var raw_thresholds: Array = GameManager.ASCENSION_THRESHOLDS.get(ship_id, [])
	if max_stage <= 0:
		return []
	var thresholds_for_stages: Array = raw_thresholds.slice(0, min(max_stage, raw_thresholds.size()))
	return thresholds_for_stages

func _get_ship_last_threshold(ship: Dictionary) -> int:
	var ship_id: String = str(ship.get("id", ""))
	var max_stage: int = int(ship.get("max_evolution_stage", 0))
	var thresholds: Array = _get_ship_thresholds_for_max_stage(ship_id, max_stage)
	if thresholds.is_empty():
		return 0
	return int(thresholds[thresholds.size() - 1])

func _get_ship_max_upgrade_cap(ship: Dictionary) -> int:
	return _get_ship_last_threshold(ship) + 5

func _get_next_evolution_requirements(ship_index: int) -> Dictionary:
	var ship = GameManager.ships[ship_index]
	var ship_id = ship["id"]
	var thresholds = _get_ship_thresholds_for_max_stage(ship_id, int(ship.get("max_evolution_stage", 0)))
	var current_stage = ship["current_evolution_stage"]

	if current_stage >= thresholds.size():
		return {"can_evolve": false, "upgrades_needed": 0}

	var next_threshold = thresholds[current_stage]
	var upgrades_needed = max(0, next_threshold - ship["upgrade_count"])

	return {
		"can_evolve": true,
		"upgrades_needed": upgrades_needed,
		"threshold": next_threshold,
		"next_evolution_name": _get_current_evolution_name(ship_id, current_stage + 1)
	}

# ================================
# PERFORMANCE OPTIMIZATIONS
# ================================
func _optimize_texture_loading() -> void:
	if not ui_refresh_service:
		return
	ui_refresh_service.optimize_texture_loading(GameManager, ship_textures_ui, selected_ship_index)

func _debug_grant_resources(crystal: int = 1000000, coin: int = 500000, void_shard: int = 500000) -> void:
	if DebugFlags.block("upgrade_menu resource grant"):
		return
	GameManager.add_currency("crystals", crystal)
	GameManager.add_currency("coins", coin)
	GameManager.add_currency("void_shards", void_shard)
	_update_currency_display()

# ================================
# INPUT HANDLING
# ================================
func _input(event: InputEvent) -> void:
	# Every shortcut below is a debug/easy-win cheat (free items, instant
	# upgrade, 1M crystals). None of it may exist in a release build.
	if not DebugFlags.enabled:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				var selected_index = event.keycode - KEY_1
				if is_satellite_tab_active:
					if selected_index < GameManager.satellites.size():
						selected_satellite_index = selected_index
						update_satellite_ui()
				else:
					if selected_index < GameManager.ships.size():
						selected_ship_index = selected_index
						update_ship_ui()
			KEY_U:
				_upgrade_selected_item("crystals")
			KEY_A:
				_ascend_selected_item()
			KEY_R:
				_debug_grant_resources()

# ================================
# CLEANUP
# ================================
func _exit_tree() -> void:
	_save_ship_progress()
	_cleanup_signals()
	if refresh_timer:
		refresh_timer.stop()
	if ad_usage_timer:
		ad_usage_timer.stop()

func _cleanup_signals() -> void:
	# Disconnect all signals to prevent memory leaks
	if GameManager.has_signal("currency_updated") and GameManager.currency_updated.is_connected(_on_currency_updated):
		GameManager.currency_updated.disconnect(_on_currency_updated)
	
	if GameManager.has_signal("ad_reward_granted") and GameManager.ad_reward_granted.is_connected(_on_ad_reward_granted):
		GameManager.ad_reward_granted.disconnect(_on_ad_reward_granted)
	
	if GameManager.has_signal("ad_failed_to_load") and GameManager.ad_failed_to_load.is_connected(_on_ad_failed_to_load):
		GameManager.ad_failed_to_load.disconnect(_on_ad_failed_to_load)
	
	# Disconnect visibility changed signal
	if is_connected("visibility_changed", _on_visibility_changed):
		disconnect("visibility_changed", _on_visibility_changed)
	
	# Disconnect back button
	var root = get_tree().get_root()
	if root and root.has_signal("go_back_requested"):
		if root.go_back_requested.is_connected(_on_back_pressed):
			root.go_back_requested.disconnect(_on_back_pressed)
	
	# Stop timers
	if refresh_timer and refresh_timer.is_inside_tree():
		refresh_timer.stop()
	if ad_usage_timer and ad_usage_timer.is_inside_tree():
		ad_usage_timer.stop()

# Add a notification handler to ensure UI is updated when the scene is ready
func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		# Update currency display when the node is ready
		call_deferred("_update_currency_display_when_ready")

# Add a helper function to update currency display with a delay
func _update_currency_display_when_ready() -> void:
	# Wait one frame to ensure all systems are initialized
	await get_tree().process_frame
	_update_currency_display()
	currency_display_updated = true

# Add a new function to show messages in the message panel
func _show_message(text: String) -> void:
	if message and msg_panel:
		message.text = text
		msg_panel.show()
		# Hide the message after a delay
		await get_tree().create_timer(1.0).timeout
		if is_inside_tree() and msg_panel:
			msg_panel.hide()

func _show_warning(text: String) -> void:
	if warning and warning_panel:
		warning.text = text
		warning_panel.show()
		# Hide the warning after a delay
		await get_tree().create_timer(1.0).timeout
		if is_inside_tree() and warning_panel:
			warning_panel.hide()

func _initialize_refresh_timer() -> void:
	refresh_timer = Timer.new()
	add_child(refresh_timer)
	refresh_timer.wait_time = 5.0  # Check every 5 seconds (reduced frequency)
	refresh_timer.timeout.connect(_on_refresh_timer_timeout)
	refresh_timer.start()

func _on_refresh_timer_timeout() -> void:
	# Periodically refresh the currency display as a fallback
	# Only update if the display hasn't been updated yet or if there's a discrepancy
	if not currency_display_updated or ui_refresh_service.is_currency_display_stale(
		GameManager,
		Crystals_display,
		Coins_display,
		void_shards_display
	):
		_update_currency_display()
		currency_display_updated = true

func _on_visibility_changed() -> void:
	# Update currency display when the scene becomes visible
	if visible:
		call_deferred("_update_currency_display")


func _on_ships_pressed() -> void:
	# Hide satellites container and show ship container
	var sat_container = get_node("UI/Satcontainer")
	var ship_container = get_node("UI/ShipContainer")
	
	if sat_container and ship_container:
		sat_container.hide()
		ship_container.show()
		is_satellite_tab_active = false
		# Update the main display to show the currently selected ship
		update_ship_ui()
		# Show/hide appropriate selection buttons
		_update_selection_buttons_visibility()


func _on_satellites_pressed() -> void:
	# Hide ship container and show satellites container
	var sat_container = get_node("UI/Satcontainer")
	var ship_container = get_node("UI/ShipContainer")
	
	if sat_container and ship_container:
		ship_container.hide()
		sat_container.show()
		is_satellite_tab_active = true
		# Update the main display to show the currently selected satellite
		update_satellite_ui()
		# Show/hide appropriate selection buttons
		_update_selection_buttons_visibility()

	# Notify tutorial that satellite tab was opened
	TutorialManager.notify_satellite_tab_opened()



func _update_current_satellite_textures() -> void:
	"""Update textures of currently active satellites in the game scene"""
	if not ui_refresh_service:
		return
	await ui_refresh_service.update_current_satellite_textures(GameManager)


func _on_shop_pressed() -> void:
	# Use GameManager's scene system to change to shop scene
	GameManager.change_scene(SHOP)

# ================================
# SATELLITE MANAGEMENT SYSTEM
# ================================

func _get_satellite_upgrade_costs() -> Dictionary:
	"""Calculate current satellite upgrade costs based on upgrade and ascend counts"""
	if GameManager.satellites.is_empty() or selected_satellite_index >= GameManager.satellites.size():
		return {"crystal_cost": 30, "coin_cost": 500, "void_shard_cost": 80}

	var satellite = GameManager.satellites[selected_satellite_index]
	if not satellite is Dictionary:
		return {"crystal_cost": 30, "coin_cost": 500, "void_shard_cost": 80}
	return transaction_service.get_satellite_upgrade_costs(ConfigLoader, satellite)

func _upgrade_satellite(satellite_index: int, currency_type: String) -> bool:
	"""Upgrade a satellite using crystals or coins"""
	var satellite = GameManager.satellites[satellite_index]
	var costs = _get_satellite_upgrade_costs()

	if not satellite["unlocked"] or satellite["can_ascend"]:
		return false

	# Check if satellite is at max rank
	if satellite["ascend_count"] >= satellite["max_evolution_stage"]:
		return false

	var payment_result := transaction_service.try_pay_upgrade_cost(GameManager, costs, currency_type)
	if not bool(payment_result.get("ok", false)):
		_show_warning("Not enough %s to upgrade %s!" % [currency_type, satellite["display_name"]])
		return false

	satellite["upgrade_count"] += 1
	_apply_satellite_stat_boost(satellite)
	_check_satellite_ascension_eligibility(satellite_index)
	power_up.play()

	if satellite_index == selected_satellite_index:
		update_satellite_ui()
		_show_details_container_temporarily(2.0)
	_update_all_satellite_textures()

	# Save progress after upgrade
	transaction_service.save_progress(GameManager)
	return true

func _apply_satellite_stat_boost(satellite: Dictionary) -> void:
	"""Apply damage bonus increase to satellite"""
	if not satellite.has("base_damage"):
		satellite["base_damage"] = int(satellite.get("damage_bonus", 0))
	if not satellite.has("damage_bonus"):
		satellite["damage_bonus"] = 0

	var damage_increase := _get_satellite_upgrade_damage_increase(satellite)
	satellite["damage_bonus"] = int(satellite["damage_bonus"]) + damage_increase
	
	# Notify GameManager that satellite stats have been updated
	GameManager.notify_satellite_stats_updated(satellite["id"], int(satellite["damage_bonus"]))

func _get_satellite_upgrade_damage_increase(satellite: Dictionary) -> int:
	var base_damage_boost = 2
	var ascend_count = int(satellite.get("ascend_count", 0))
	var stage_multiplier = 1.0 + (ascend_count * 0.2)
	return int(base_damage_boost * stage_multiplier)

func _get_satellite_total_damage(satellite: Dictionary) -> int:
	var base_damage: int = int(satellite.get("base_damage", satellite.get("damage_bonus", 0)))
	var damage_bonus: int = int(satellite.get("damage_bonus", 0))
	return max(1, base_damage + damage_bonus)

func _check_satellite_ascension_eligibility(satellite_index: int) -> void:
	"""Check if satellite has reached ascension threshold"""
	var satellite = GameManager.satellites[satellite_index]
	var satellite_id = satellite["id"]
	var thresholds = GameManager.SATELLITE_ASCENSION_THRESHOLDS.get(satellite_id, [])
	var ascend_count = satellite["ascend_count"]

	if ascend_count < thresholds.size() and satellite["upgrade_count"] >= thresholds[ascend_count]:
		satellite["can_ascend"] = true

func _ascend_satellite(satellite_index: int) -> bool:
	"""Ascend satellite to increase rank"""
	var satellite = GameManager.satellites[satellite_index]
	var costs = _get_satellite_upgrade_costs()

	if not satellite["unlocked"] or not satellite["can_ascend"]:
		return false

	var payment_result := transaction_service.try_pay_ascend_cost(GameManager, costs)
	if not bool(payment_result.get("ok", false)):
		_show_warning("Not enough void shards to ascend %s!" % satellite["display_name"])
		return false

	# Increment both counters
	satellite["upgrade_count"] += 1
	satellite["ascend_count"] += 1

	# Apply evolution bonus
	var evolution_bonus = _get_satellite_evolution_bonus(satellite["id"], satellite["ascend_count"])
	if not satellite.has("base_damage"):
		satellite["base_damage"] = int(satellite.get("damage_bonus", 0))
	if not satellite.has("damage_bonus"):
		satellite["damage_bonus"] = 0
	satellite["damage_bonus"] = int(satellite["damage_bonus"]) + evolution_bonus

	# Update rank if reached max evolution stage
	if satellite["ascend_count"] >= satellite["max_evolution_stage"]:
		satellite["rank"] = satellite["final_rank"]

	satellite["can_ascend"] = false

	# Notify GameManager that satellite stats have been updated
	GameManager.notify_satellite_stats_updated(satellite["id"], int(satellite["damage_bonus"]))

	power_up.play()
	_show_message("Satellite %s rank increased to %s!" % [satellite["display_name"], satellite["rank"]])

	if satellite_index == selected_satellite_index:
		update_satellite_ui()
	_update_all_satellite_textures()

	# Save progress after ascension
	transaction_service.save_progress(GameManager)
	return true

func _get_satellite_evolution_bonus(satellite_id: String, ascend_count: int) -> int:
	"""Calculate evolution bonus for satellite ascension"""
	var base_bonus = 10
	var rarity_multiplier = _get_satellite_rarity_multiplier(satellite_id)
	var stage_multiplier = 1.0 + (ascend_count * 0.5)

	return int(base_bonus * rarity_multiplier * stage_multiplier)

func _get_satellite_rarity_multiplier(satellite_id: String) -> float:
	"""Get rarity multiplier for satellite based on current rank"""
	var satellite = _get_satellite_by_id(satellite_id)
	if not satellite:
		return 1.0

	match satellite["rank"]:
		"R": return 1.0
		"SR": return 1.3
		"SSR": return 1.6
		"LR": return 2.0
		_: return 1.0

func _get_satellite_by_id(satellite_id: String) -> Dictionary:
	"""Find satellite by ID in GameManager.satellites array"""
	for satellite in GameManager.satellites:
		if satellite["id"] == satellite_id:
			return satellite
	return {}

func _purchase_satellite(satellite_index: int) -> bool:
	"""Purchase a locked satellite"""
	var satellite = GameManager.satellites[satellite_index]
	var result := transaction_service.try_purchase_unlock(GameManager, satellite, "crystals")
	if not bool(result.get("ok", false)):
		var error_code := str(result.get("error", "unknown"))
		if error_code == "insufficient_funds":
			_show_warning("Not enough crystals to purchase %s!" % satellite["display_name"])
		return false

	_update_all_satellite_textures()
	if satellite_index == selected_satellite_index:
		update_satellite_ui()
	var action_text := "unlocked" if bool(result.get("was_free", false)) else "purchased"
	_show_message("%s %s!" % [satellite["display_name"], action_text])
	_update_currency_display()
	# The campaign now walks the player from BUY to the equip button.
	TutorialManager.notify_satellite_purchased()
	return true

func _purchase_ship(ship_index: int) -> bool:
	var ship = GameManager.ships[ship_index]
	var result := transaction_service.try_purchase_unlock(GameManager, ship, "crystals")
	if not bool(result.get("ok", false)):
		var error_code := str(result.get("error", "unknown"))
		if error_code == "insufficient_funds":
			_show_insufficient_funds_message(ship["display_name"], "crystals")
		return false

	_update_all_ship_textures()
	if ship_index == selected_ship_index:
		update_ship_ui()
	var action_text := "unlocked" if bool(result.get("was_free", false)) else "purchased"
	_show_message("%s %s!" % [ship["display_name"], action_text])
	_update_currency_display()
	return true


func _on_sat_1_gui_input(event: InputEvent) -> void:
	_handle_satellite_selection(event, 0)


func _on_sat_2_gui_input(event: InputEvent) -> void:
	_handle_satellite_selection(event, 1)


func _on_sat_3_gui_input(event: InputEvent) -> void:
	_handle_satellite_selection(event, 2)


func _on_sat_4_gui_input(event: InputEvent) -> void:
	_handle_satellite_selection(event, 3)


func _on_sat_5_gui_input(event: InputEvent) -> void:
	_handle_satellite_selection(event, 4)


func _on_sat_6_gui_input(event: InputEvent) -> void:
	_handle_satellite_selection(event, 5)


func _on_sat_left_select_pressed() -> void:
	# When player selects left satellite, equip the currently selected satellite in the left position
	var satellite = GameManager.satellites[selected_satellite_index]
	var result := selection_service.equip_satellite_left(GameManager, PlayerManager, satellite)
	if bool(result.get("ok", false)):
		PlayerManager.update_selected_satellites()
		_show_message(str(result.get("message", "")))
		TutorialManager.notify_satellite_equipped()


func _on_sat_right_select_pressed() -> void:
	# When player selects right satellite, equip the currently selected satellite in the right position
	var satellite = GameManager.satellites[selected_satellite_index]
	var result := selection_service.equip_satellite_right(GameManager, PlayerManager, satellite)
	if bool(result.get("ok", false)):
		PlayerManager.update_selected_satellites()
		_show_message(str(result.get("message", "")))
		TutorialManager.notify_satellite_equipped()


func _on_selected_ship_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Toggle visibility of the details container
		if details_container:
			if details_container.visible:
				details_container.hide()
			else:
				details_container.show()
