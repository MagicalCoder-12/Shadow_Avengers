extends Control

const FREE_TEXT := "Free"
const WATCH_AD_TEXT := "Watch Ad"
const NO_ADS_TEXT := "No Ads Left"
const NO_SPINS_TEXT := "No Spins Left"

const BASE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const DISABLED_COLOR := Color(0.6, 0.6, 0.6, 1.0)
const IDLE_GLOW_COLOR := Color(1.08, 1.08, 1.12, 1.0)
const HIGHLIGHT_COLOR := Color(1.18, 1.18, 1.2, 1.0)
const BORDER_HIDDEN_MODULATE := Color(1.0, 0.86, 0.15, 0.0)
const BORDER_HIGHLIGHT_MODULATE := Color(1.2, 1.12, 0.65, 1.0)
const BORDER_COLOR := Color(1.0, 0.86, 0.15, 0.98)
const BORDER_NAME := "GlowBorder"
const HOVER_BORDER_NAME := "HoverBorder"
const HOVER_BORDER_COLOR := Color(1.0, 0.86, 0.15, 0.98)
const HOVER_HIGHLIGHT := Color(1.15, 1.15, 1.2, 1.0)

const SPIN_MIN_LOOPS := 1
const SPIN_MAX_LOOPS := 2
const SPIN_START_DELAY := 0.03
const SPIN_MAX_DELAY := 0.16
const SPIN_DELAY_STEP := 0.012
const RESULT_SHOWCASE_DURATION := 2.0
const DIMMED_PANEL_COLOR := Color(0.32, 0.32, 0.36, 0.45)
const SELECTED_PANEL_COLOR := Color(1.22, 1.22, 1.24, 1.0)
const DIMMED_CONTENT_COLOR := Color(0.42, 0.42, 0.46, 0.45)
const SELECTED_CONTENT_COLOR := Color(1.0, 1.0, 1.0, 1.0)

@onready var free_button: Button = $PanelContainer/Panel/HBoxContainer/Free/freeButton
@onready var free_label: Label = $PanelContainer/Panel/HBoxContainer/Free/free_Label
@onready var crystal_button: Button = $PanelContainer/Panel/HBoxContainer/Crystal/crystal_Button
@onready var crystal_label: Label = $PanelContainer/Panel/HBoxContainer/Crystal/HBoxContainer/Label
@onready var spins_left: Label = $PanelContainer/Panel/GridContainer/Panel5/SpinsLeft
@onready var void_shards_display: Label = $Resources/VoidCrystal/Void_Shards_display
@onready var crystals_display: Label = $Resources/Crystal/Crystals_display
@onready var coins_display: Label = $Resources/Money/Coins_display
@onready var grid_container: GridContainer = $PanelContainer/Panel/GridContainer
@onready var panel_container: PanelContainer = $PanelContainer
@onready var center_panel: Panel = $PanelContainer/Panel/GridContainer/Panel5
@onready var free_card: Control = $PanelContainer/Panel/HBoxContainer/Free
@onready var crystal_card: Control = $PanelContainer/Panel/HBoxContainer/Crystal
@onready var wheel: Control = $"."
@onready var warning_panel: Panel = $WarningPanel
@onready var warning_label: Label = $WarningPanel/Warning_Label
@onready var coin_sound: AudioStreamPlayer = $CoinCollected08

var reward_panels: Array[Panel] = []
var _idle_glow_tweens: Array[Tween] = []
var _spin_in_progress: bool = false
var _ad_request_in_progress: bool = false
var _current_highlight_index: int = -1
var _warning_tween: Tween
var _free_press_tween: Tween
var _crystal_press_tween: Tween
var _popup_tween: Tween

func _ready() -> void:
	randomize()
	_collect_reward_panels()
	_start_idle_glow()
	_connect_game_manager_signals()
	_connect_button_feedback_signals()
	_refresh_button_pivots()
	_hide_warning_panel_immediately()
	_refresh_ui()
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)

func _exit_tree() -> void:
	if GameManager:
		if GameManager.ad_reward_granted.is_connected(_on_ad_reward_granted):
			GameManager.ad_reward_granted.disconnect(_on_ad_reward_granted)
		if GameManager.ad_failed_to_load.is_connected(_on_ad_failed_to_load):
			GameManager.ad_failed_to_load.disconnect(_on_ad_failed_to_load)
		if GameManager.currency_updated.is_connected(_on_currency_updated):
			GameManager.currency_updated.disconnect(_on_currency_updated)
	if free_button.button_down.is_connected(_on_free_button_down):
		free_button.button_down.disconnect(_on_free_button_down)
	if free_button.mouse_entered.is_connected(_on_free_button_mouse_entered):
		free_button.mouse_entered.disconnect(_on_free_button_mouse_entered)
	if free_button.mouse_exited.is_connected(_on_free_button_mouse_exited):
		free_button.mouse_exited.disconnect(_on_free_button_mouse_exited)
	if crystal_button.button_down.is_connected(_on_crystal_button_down):
		crystal_button.button_down.disconnect(_on_crystal_button_down)
	if crystal_button.mouse_entered.is_connected(_on_crystal_button_mouse_entered):
		crystal_button.mouse_entered.disconnect(_on_crystal_button_mouse_entered)
	if crystal_button.mouse_exited.is_connected(_on_crystal_button_mouse_exited):
		crystal_button.mouse_exited.disconnect(_on_crystal_button_mouse_exited)
	if _popup_tween:
		_popup_tween.kill()

func _on_visibility_changed() -> void:
	if visible:
		_refresh_button_pivots()
		_hide_warning_panel_immediately()
		_refresh_ui()
		_update_resource_display()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not GameManager:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_D:
		GameManager.reset_wheel_state(true)
		GameManager.save_progress_if_enabled()
		_hide_warning_panel_immediately()
		_refresh_ui()
		_show_warning("Debug: wheel spins reset to 10.", 1.6)

func popup_open() -> void:
	show()
	_refresh_button_pivots()
	_hide_warning_panel_immediately()
	_refresh_ui()
	if _popup_tween:
		_popup_tween.kill()
	wheel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	panel_container.scale = Vector2(0.88, 0.88)
	panel_container.pivot_offset = panel_container.size * 0.5
	_popup_tween = create_tween()
	_popup_tween.tween_property(wheel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_popup_tween.parallel().tween_property(panel_container, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _connect_game_manager_signals() -> void:
	if not GameManager:
		return
	if GameManager.has_signal("ad_reward_granted"):
		if not GameManager.ad_reward_granted.is_connected(_on_ad_reward_granted):
			GameManager.ad_reward_granted.connect(_on_ad_reward_granted)
	if GameManager.has_signal("ad_failed_to_load"):
		if not GameManager.ad_failed_to_load.is_connected(_on_ad_failed_to_load):
			GameManager.ad_failed_to_load.connect(_on_ad_failed_to_load)
	if GameManager.has_signal("currency_updated"):
		if not GameManager.currency_updated.is_connected(_on_currency_updated):
			GameManager.currency_updated.connect(_on_currency_updated)

func _connect_button_feedback_signals() -> void:
	if not free_button.button_down.is_connected(_on_free_button_down):
		free_button.button_down.connect(_on_free_button_down)
	if not crystal_button.button_down.is_connected(_on_crystal_button_down):
		crystal_button.button_down.connect(_on_crystal_button_down)
	if not free_button.mouse_entered.is_connected(_on_free_button_mouse_entered):
		free_button.mouse_entered.connect(_on_free_button_mouse_entered)
	if not free_button.mouse_exited.is_connected(_on_free_button_mouse_exited):
		free_button.mouse_exited.connect(_on_free_button_mouse_exited)
	if not crystal_button.mouse_entered.is_connected(_on_crystal_button_mouse_entered):
		crystal_button.mouse_entered.connect(_on_crystal_button_mouse_entered)
	if not crystal_button.mouse_exited.is_connected(_on_crystal_button_mouse_exited):
		crystal_button.mouse_exited.connect(_on_crystal_button_mouse_exited)

func _on_currency_updated(_currency_type: String, _new_amount: int) -> void:
	_update_resource_display()

func _format_number(num: int) -> String:
	if num >= 1000000000:
		return "%.1fB" % (num / 1000000000.0)
	elif num >= 1000000:
		return "%.1fM" % (num / 1000000.0)
	elif num >= 1000:
		return "%.1fK" % (num / 1000.0)
	return str(num)

func _update_resource_display() -> void:
	if not GameManager:
		return
	if crystals_display:
		crystals_display.text = "Crystals: %s" % _format_number(int(GameManager.crystal_count))
	if coins_display:
		coins_display.text = "Coins: %s" % _format_number(int(GameManager.coin_count))
	if void_shards_display:
		void_shards_display.text = "Void Shards: %s" % _format_number(int(GameManager.void_shards_count))

func _on_free_button_down() -> void:
	_play_button_press_feedback(free_card, true)

func _on_crystal_button_down() -> void:
	_play_button_press_feedback(crystal_card, false)

func _ensure_card_hover_border(card: Control) -> Panel:
	var border := card.get_node_or_null(HOVER_BORDER_NAME) as Panel
	if border:
		return border
	border = Panel.new()
	border.name = HOVER_BORDER_NAME
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.focus_mode = Control.FOCUS_NONE
	border.z_index = 10
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.offset_left = 4
	border.offset_top = 4
	border.offset_right = -4
	border.offset_bottom = -4
	var border_style := StyleBoxFlat.new()
	border_style.draw_center = false
	border_style.border_color = HOVER_BORDER_COLOR
	border_style.set_border_width_all(6)
	border_style.set_corner_radius_all(16)
	border.add_theme_stylebox_override("panel", border_style)
	card.add_child(border)
	return border

func _on_free_button_mouse_entered() -> void:
	if not free_button.disabled:
		free_card.modulate = HOVER_HIGHLIGHT
		var border := _ensure_card_hover_border(free_card)
		border.show()

func _on_free_button_mouse_exited() -> void:
	free_card.modulate = Color.WHITE
	var border := free_card.get_node_or_null(HOVER_BORDER_NAME) as Panel
	if border:
		border.hide()

func _on_crystal_button_mouse_entered() -> void:
	if not crystal_button.disabled:
		crystal_card.modulate = HOVER_HIGHLIGHT
		var border := _ensure_card_hover_border(crystal_card)
		border.show()

func _on_crystal_button_mouse_exited() -> void:
	crystal_card.modulate = Color.WHITE
	var border := crystal_card.get_node_or_null(HOVER_BORDER_NAME) as Panel
	if border:
		border.hide()

func _collect_reward_panels() -> void:
	reward_panels.clear()
	for child in grid_container.get_children():
		if child is Panel and child.name != "Panel5":
			var panel := child as Panel
			if panel:
				reward_panels.append(panel)
				_ensure_panel_border(panel)

func _ensure_panel_border(panel: Panel) -> void:
	var border := panel.get_node_or_null(BORDER_NAME) as Panel
	if border:
		return
	border = Panel.new()
	border.name = BORDER_NAME
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.focus_mode = Control.FOCUS_NONE
	border.z_index = 10
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.offset_left = 6.0
	border.offset_top = 6.0
	border.offset_right = -6.0
	border.offset_bottom = -6.0
	border.self_modulate = BORDER_HIDDEN_MODULATE
	var border_style := StyleBoxFlat.new()
	border_style.draw_center = false
	border_style.border_color = BORDER_COLOR
	border_style.set_border_width_all(8)
	border_style.set_corner_radius_all(26)
	panel.add_child(border)
	border.add_theme_stylebox_override("panel", border_style)

func _start_idle_glow() -> void:
	_stop_idle_glow()
	center_panel.self_modulate = BASE_COLOR
	for panel in reward_panels:
		panel.self_modulate = BASE_COLOR
		_set_panel_texture_modulate(panel, BASE_COLOR)
		var border := _get_panel_border(panel)
		if border:
			border.self_modulate = BORDER_HIDDEN_MODULATE
		var tween: Tween = panel.create_tween()
		tween.set_loops()
		tween.tween_property(panel, "self_modulate", IDLE_GLOW_COLOR, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(panel, "self_modulate", BASE_COLOR, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_idle_glow_tweens.append(tween)

func _stop_idle_glow() -> void:
	for tween in _idle_glow_tweens:
		if tween:
			tween.kill()
	_idle_glow_tweens.clear()

func _highlight_panel(index: int) -> void:
	_current_highlight_index = index
	for i in range(reward_panels.size()):
		var panel: Panel = reward_panels[i]
		var border := _get_panel_border(panel)
		panel.self_modulate = HIGHLIGHT_COLOR if i == index else BASE_COLOR
		_set_panel_texture_modulate(panel, SELECTED_CONTENT_COLOR if i == index else BASE_COLOR)
		if border:
			border.self_modulate = BORDER_HIGHLIGHT_MODULATE if i == index else BORDER_HIDDEN_MODULATE

func _showcase_selected_panel(index: int) -> void:
	_current_highlight_index = index
	center_panel.self_modulate = DIMMED_PANEL_COLOR
	for i in range(reward_panels.size()):
		var panel: Panel = reward_panels[i]
		var border := _get_panel_border(panel)
		panel.self_modulate = SELECTED_PANEL_COLOR if i == index else DIMMED_PANEL_COLOR
		_set_panel_texture_modulate(panel, SELECTED_CONTENT_COLOR if i == index else DIMMED_CONTENT_COLOR)
		if border:
			border.self_modulate = BORDER_HIGHLIGHT_MODULATE if i == index else BORDER_HIDDEN_MODULATE

func _refresh_ui() -> void:
	if not GameManager:
		return
	GameManager.reset_wheel_daily_if_needed()
	_update_resource_display()
	var max_spins: int = GameManager.get_wheel_daily_max_spins()
	var spins_remaining: int = GameManager.get_wheel_spins_remaining()
	spins_left.text = "Spins Left: %d/%d" % [spins_remaining, max_spins]
	var can_free: bool = GameManager.can_use_wheel_free_spin()
	var can_ad: bool = GameManager.can_use_wheel_ad_spin()
	var ad_remaining: int = GameManager.get_wheel_ad_spins_remaining()
	var ad_limit: int = GameManager.get_wheel_ad_spin_limit()
	if spins_remaining <= 0:
		free_label.text = NO_SPINS_TEXT
	elif can_free:
		free_label.text = FREE_TEXT
	elif ad_remaining > 0:
		free_label.text = "%s (%d/%d)" % [WATCH_AD_TEXT, ad_remaining, ad_limit]
	else:
		free_label.text = NO_ADS_TEXT
	var free_enabled: bool = (can_free or can_ad) and spins_remaining > 0
	free_enabled = free_enabled and not _spin_in_progress and not _ad_request_in_progress
	free_button.disabled = not free_enabled
	free_label.modulate = BASE_COLOR if free_enabled else DISABLED_COLOR
	var cost: int = GameManager.get_wheel_crystal_spin_cost()
	crystal_label.text = "%d" % cost
	var paid_enabled: bool = GameManager.can_use_wheel_paid_spin()
	paid_enabled = paid_enabled and not _spin_in_progress and not _ad_request_in_progress
	crystal_button.disabled = not paid_enabled
	crystal_label.modulate = BASE_COLOR if paid_enabled else DISABLED_COLOR

func _on_free_button_pressed() -> void:
	if _spin_in_progress or _ad_request_in_progress:
		return
	if not GameManager:
		return
	_hide_warning_panel_immediately()
	GameManager.reset_wheel_daily_if_needed()
	if GameManager.try_use_wheel_free_spin():
		if coin_sound:
			coin_sound.play()
		await _perform_spin()
		return
	if GameManager.can_use_wheel_ad_spin():
		var result: Dictionary = GameManager.request_wheel_ad_spin()
		if result.get("ok", false):
			_ad_request_in_progress = true
		else:
			_show_warning(_friendly_ad_message(result.get("message", "")))
	elif GameManager.get_wheel_spins_remaining() <= 0:
		_show_warning("You have used all of today's wheel spins.")
	else:
		_show_warning("No free ad spins are left right now. Come back tomorrow.")
	_refresh_ui()

func _on_crystal_button_pressed() -> void:
	if _spin_in_progress or _ad_request_in_progress:
		return
	if not GameManager:
		return
	_hide_warning_panel_immediately()
	var result: Dictionary = GameManager.try_use_wheel_paid_spin()
	if result.get("ok", false):
		await _perform_spin()
	else:
		_show_warning(_friendly_paid_spin_message(result))
	_refresh_ui()

func _on_ad_reward_granted(ad_type: String) -> void:
	if ad_type != "wheel_spin":
		return
	_ad_request_in_progress = false
	if not GameManager:
		return
	if GameManager.consume_wheel_ad_spin_reward():
		await _perform_spin()
	_refresh_ui()

func _on_ad_failed_to_load(ad_type: String, _error_data: Variant) -> void:
	if ad_type != "wheel_spin":
		return
	_ad_request_in_progress = false
	if GameManager:
		GameManager.cancel_wheel_ad_spin_pending()
	_show_warning(_friendly_ad_error_message(_error_data))
	_refresh_ui()

func _perform_spin() -> void:
	if reward_panels.is_empty():
		_refresh_ui()
		return
	_spin_in_progress = true
	_stop_idle_glow()
	var loops: int = randi_range(SPIN_MIN_LOOPS, SPIN_MAX_LOOPS)
	var target_index: int = randi_range(0, reward_panels.size() - 1)
	var steps: int = loops * reward_panels.size() + target_index
	var delay: float = SPIN_START_DELAY
	for step in range(steps + 1):
		if not is_inside_tree():
			_spin_in_progress = false
			return
		_highlight_panel(step % reward_panels.size())
		await get_tree().create_timer(delay, true).timeout
		delay = min(delay + SPIN_DELAY_STEP, SPIN_MAX_DELAY)
	if not is_inside_tree():
		_spin_in_progress = false
		return
	_showcase_selected_panel(target_index)
	await get_tree().create_timer(RESULT_SHOWCASE_DURATION, true).timeout
	if not is_inside_tree():
		_spin_in_progress = false
		return
	_apply_reward(reward_panels[target_index])
	_spin_in_progress = false
	_start_idle_glow()
	_refresh_ui()

func _apply_reward(panel: Panel) -> void:
	if not GameManager:
		return
	var reward: Dictionary = _get_reward_from_panel(panel)
	if reward.is_empty():
		return
	var amount: int = int(reward.get("amount", 0))
	var currency: String = str(reward.get("currency", "coins"))
	if amount <= 0:
		return
	GameManager.add_currency(currency, amount)


func _get_panel_border(panel: Panel) -> Panel:
	return panel.get_node_or_null(BORDER_NAME) as Panel

func _set_panel_texture_modulate(panel: Panel, color: Color) -> void:
	var texture_rect := panel.get_node_or_null("TextureRect") as TextureRect
	if texture_rect:
		texture_rect.self_modulate = color

func _refresh_button_pivots() -> void:
	free_card.pivot_offset = free_card.size * 0.5
	crystal_card.pivot_offset = crystal_card.size * 0.5

func _play_button_press_feedback(target: Control, is_free_button: bool) -> void:
	target.pivot_offset = target.size * 0.5
	var active_tween: Tween = _free_press_tween if is_free_button else _crystal_press_tween
	if active_tween:
		active_tween.kill()
	target.scale = Vector2.ONE
	var tween: Tween = target.create_tween()
	tween.tween_property(target, "scale", Vector2(0.8, 0.8), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "scale", Vector2.ONE, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_free_button:
		_free_press_tween = tween
	else:
		_crystal_press_tween = tween

func _show_warning(message: String, duration: float = 2.5) -> void:
	_cancel_warning_tween()
	warning_label.text = message
	warning_panel.show()
	_warning_tween = warning_panel.create_tween()
	_warning_tween.tween_interval(duration)
	_warning_tween.tween_callback(Callable(self, "_hide_warning_after_timeout"))

func _hide_warning_panel_immediately() -> void:
	_cancel_warning_tween()
	warning_panel.hide()

func _hide_warning_after_timeout() -> void:
	warning_panel.hide()
	_warning_tween = null

func _cancel_warning_tween() -> void:
	if _warning_tween:
		_warning_tween.kill()
		_warning_tween = null

func _friendly_paid_spin_message(result: Dictionary) -> String:
	var error_code := str(result.get("error", ""))
	match error_code:
		"currency":
			return "You need %d crystals for another spin." % GameManager.get_wheel_crystal_spin_cost()
		"limit":
			return "You have used all of today's wheel spins."
	var message := str(result.get("message", ""))
	if not message.is_empty():
		return message
	return "The wheel could not start right now. Please try again."

func _friendly_ad_message(raw_message: Variant) -> String:
	var normalized := str(raw_message).to_lower()
	if normalized.find("already") != -1 or normalized.find("progress") != -1 or normalized.find("pending") != -1:
		return "An ad is already opening. Please wait a moment."
	if normalized.find("unavailable") != -1 or normalized.find("not available") != -1:
		return "Ads are not available right now. Please try again in a little while."
	return "We could not open the ad right now. Please try again in a moment."

func _friendly_ad_error_message(error_data: Variant) -> String:
	var raw_message := ""
	if error_data is Dictionary:
		raw_message = str(error_data.get("message", ""))
	else:
		raw_message = str(error_data)
	var normalized := raw_message.to_lower()
	if normalized.find("closed before reward") != -1 or normalized.find("dismiss") != -1 or normalized.find("cancel") != -1:
		return "The ad was closed before it finished, so your free spin was not used."
	if normalized.find("timed out") != -1:
		return "The ad took too long to load. Please try again."
	if normalized.find("unavailable") != -1 or normalized.find("not available") != -1:
		return "Ads are not available right now. Please try again in a little while."
	if normalized.find("load") != -1 or normalized.find("show") != -1 or normalized.find("fill") != -1:
		return "We could not show the ad right now. Please try again in a moment."
	return "Something went wrong while opening the ad. Please try again."

func _get_reward_from_panel(panel: Panel) -> Dictionary:
	var label := panel.get_node_or_null("Label") as Label
	if not label:
		return {}
	var amount: int = int(label.text.strip_edges())
	var currency := "crystals"
	var texture_rect := panel.get_node_or_null("TextureRect") as TextureRect
	if texture_rect and texture_rect.texture:
		var path := texture_rect.texture.resource_path.to_lower()
		if path.find("coin") != -1:
			currency = "coins"
	return {
		"currency": currency,
		"amount": amount
	}


func _on_close_pressed() -> void:
	_hide_warning_panel_immediately()
	wheel.hide()
