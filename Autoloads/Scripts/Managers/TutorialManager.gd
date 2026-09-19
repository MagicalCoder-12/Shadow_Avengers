extends Node

## Central campaign tutorial director. It persists each checkpoint so a new
## profile can resume safely, while established saves are never forced into it.

const TUTORIAL_OVERLAY := preload("res://UI/TutorialOverlay.tscn")
const CORE_ONBOARDING_ID := "core_onboarding"
const SHADOW_MODE_ID := "shadow_mode"
const STAGE_COMPLETE := "complete"

var _active_id: String = ""
var _active_step: Dictionary = {}
var _tutorial_layer: CanvasLayer
var _overlay: TutorialOverlay
var _slow_motion_active: bool = false
var _previous_time_scale: float = 1.0
var _clearing: bool = false  # True while a fade-out is in progress

func get_campaign_stage() -> String:
	if SaveManager and SaveManager.has_method("get_tutorial_campaign_stage"):
		return SaveManager.get_tutorial_campaign_stage()
	return STAGE_COMPLETE

func is_new_player_campaign_active() -> bool:
	return SaveManager and bool(SaveManager.tutorial_state.get("eligible_for_automatic_tutorials", false)) and get_campaign_stage() != STAGE_COMPLETE

func should_route_to_level_zero() -> bool:
	return is_new_player_campaign_active() and get_campaign_stage() == "level0_intro"

func can_open_shop() -> bool:
	if not is_new_player_campaign_active():
		return true
	var stage := get_campaign_stage()
	return stage in ["shop_entry", "shop_reward", "shop_satellite_equip"]

func can_upgrade_in_shop() -> bool:
	if not is_new_player_campaign_active():
		return true
	var stage := get_campaign_stage()
	return stage == "shop_upgrade" or stage == "shop_satellite_upgrade"

func can_exit_shop() -> bool:
	return not is_new_player_campaign_active() or get_campaign_stage() == "shop_exit"

func can_start_level(level_num: int) -> bool:
	if not is_new_player_campaign_active():
		return true
	return level_num == 1 and get_campaign_stage() == "level1_entry"

func start_level_zero() -> bool:
	var stage := get_campaign_stage()
	if stage != "level0_intro" and _is_in_progress_level_stage(stage):
		_set_stage("level0_intro")
	elif stage != "level0_intro":
		return false
	return _show_step("level0_intro", {
		"text": "Shadow pilot, this is a beginning . Your cannons fire automatically; focus on movement and survival.",
		"status": "Tap NEXT to deploy.", "completion": "continue", "next_stage": "level0_bullet",
		"allow_player_input": false, "dim_amount": 0.50, "allow_skip": false
	})

# The bullet, coin, and powerup steps are now chained sequentially via
# next_stage in start_level_zero, so these event-driven callbacks are
# no longer needed. They are kept as empty stubs to avoid breaking
# existing call sites in EnemyCombatService, coins.gd, and Powerup.gd.

func notify_enemy_bullet_spawned(_bullet: Node) -> void:
	pass

func notify_pickup_spawned(_kind: String, _pickup: Node) -> void:
	pass

func notify_pickup_collected(_kind: String) -> void:
	pass

func handle_tutorial_death(player: Node) -> bool:
	if get_campaign_stage() == STAGE_COMPLETE or int(GameManager.get_current_level()) != 0 or not is_instance_valid(player):
		return false
	if player.has_method("set_lives"):
		player.call("set_lives", 3)
	if player.has_method("_play_death_animation"):
		player.call("_play_death_animation")
	if player.has_method("revive"):
		player.call("revive", 3)
	if _active_id.is_empty():
		_show_step("level0_revive", {
			"text": "Emergency recovery engaged. I restored your fighter this time, Shadow pilot—but do not rely on it in combat.",
			"status": "Tap NEXT and continue the sortie.", "completion": "continue", "next_stage": "level0_combat",
			"allow_player_input": false, "dim_amount": 0.50, "allow_skip": false
		})
	return true

func complete_level_zero() -> bool:
	if int(GameManager.get_current_level()) != 0 or not is_new_player_campaign_active():
		return false
	_set_stage("shop_entry")
	_clear_overlay(true)
	GameManager.change_scene(GameManager.get_map_scene_path())
	return true

func on_map_ready() -> void:
	match get_campaign_stage():
		"shop_entry", "shop_reward", "shop_upgrade", "shop_satellite_tab", "shop_satellite_upgrade", "shop_satellite_equip", "shop_exit":
			_show_step("map_shop", {"text": "Training complete. Open the Ship Hanger To upgrade ship.", "status": "Tap SHOP.", "completion": "external", "allow_player_input": true, "dim_amount": 0.45, "allow_skip": false, "target_path": "CanvasLayer/Shop"})
		"level1_entry":
			_show_step("map_level1", {"text": "Your fighter is stronger now. Select Level 1—the real operation starts here.", "status": "Tap Level 1.", "completion": "external", "allow_player_input": true, "dim_amount": 0.45, "allow_skip": false, "target_path": "LevelButtons/LevelButton1"})
		"shadow_map_intro":
			_show_step("shadow_map", {"text": "Shadow Drive unlocked. In Level 6, destroy enemies to fill its gauge, then release it when READY.", "status": "Tap NEXT to continue.", "completion": "continue", "next_stage": "shadow_charge_explained", "allow_player_input": false, "dim_amount": 0.5, "allow_skip": false})

## Step 1 of the shop visit: highlight the resource bar so the player connects
## the payout they just earned with the upgrade they are about to buy. Without
## this the upgrade prompt arrives with no context for what was received.
func _shop_reward_step_def() -> Dictionary:
	var coins := int(GameManager.coin_count)
	var crystals := int(GameManager.crystal_count)
	return {
		"text": "Training payout received, pilot. %d coins and %d crystals are in your account - check them up here before you spend a single one." % [coins, crystals],
		"status": "+%d coins, +%d crystals" % [coins, crystals],
		"completion": "continue", "next_stage": "shop_upgrade",
		"allow_player_input": true, "dim_amount": 0.45, "allow_skip": false,
		"target_path": "Resources",
	}

## Step 2 of the shop visit: spend the allowance on the first ship upgrade.
func _shop_upgrade_step_def() -> Dictionary:
	return {"text": "Command has issued an upgrade allowance. Spend it on this ship now.", "status": "Use the coin upgrade button.", "completion": "external", "allow_player_input": true, "dim_amount": 0.35, "allow_skip": false, "target_path": "UI/HBoxContainer/Upgrade_coins"}

func notify_shop_opened() -> void:
	var stage := get_campaign_stage()
	if stage != "shop_entry" and stage != "shop_reward" and stage != "shop_upgrade":
		return
	if stage == "shop_entry":
		# The payout reveal is what the player should see first inside the shop.
		_set_stage("shop_reward")

func on_shop_ready(shop: Node) -> void:
	var stage := get_campaign_stage()
	if stage != "shop_upgrade" and stage != "shop_entry" and stage != "shop_reward" and stage != "shop_satellite_equip":
		return
	# If they just arrived from the map (stage is still shop_entry), the payout
	# reveal comes before any upgrade prompt.
	if stage == "shop_entry":
		_set_stage("shop_reward")
	if not SaveManager.get_tutorial_flag("shop_investment_granted"):
		var cost: int = 0
		if shop and shop.has_method("_get_current_upgrade_costs"):
			var costs: Variant = shop.call("_get_current_upgrade_costs")
			if costs is Dictionary:
				cost = int(costs.get("coin_cost", 0))
		if cost > 0:
			GameManager.add_currency("coins", cost)
		SaveManager.set_tutorial_flag("shop_investment_granted")
	match get_campaign_stage():
		"shop_reward":
			_show_step("shop_reward", _shop_reward_step_def())
		"shop_satellite_equip":
			_show_step("shop_satellite_equip", _shop_satellite_equip_step_def())
		_:
			_show_step("shop_upgrade", _shop_upgrade_step_def())

func notify_upgrade_completed() -> void:
	if get_campaign_stage() != "shop_upgrade":
		return
	_set_stage("shop_satellite_tab")
	_clear_overlay(true)
	_show_step("shop_satellite_tab", {"text": "Ship upgraded. Now open the Satellites panel to equip a companion drone.", "status": "Tap SATELLITES.", "completion": "external", "allow_player_input": true, "dim_amount": 0.35, "allow_skip": false, "target_path": "UI/Bottom_ui/Bottom/HBoxContainer/Satellites"})

func notify_satellite_tab_opened() -> void:
	if get_campaign_stage() != "shop_satellite_tab":
		return
	_set_stage("shop_satellite_upgrade")
	_clear_overlay(true)
	_show_step("shop_satellite_upgrade", {"text": "Select a satellite and upgrade it to boost your firepower.", "status": "Tap the BUY button.", "completion": "external", "allow_player_input": true, "dim_amount": 0.35, "allow_skip": false, "target_paths": [{"path": "UI/Buy_Ascend/Buy", "status": "Tap the BUY button."}, {"path": "UI/HBoxContainer/Upgrade_coins", "status": "Use the coin upgrade button."}]})

## Step 3 of the shop visit: the satellite is bought, so the next real action
## is equipping it. The old flow demanded a coin upgrade here and then announced
## "satellite equipped" without the player ever equipping anything.
func _shop_satellite_equip_step_def() -> Dictionary:
	return {"text": "Satellite secured. Equip it now so it flies with you into the next mission.", "status": "Tap SELECT to equip.", "completion": "external", "allow_player_input": true, "dim_amount": 0.35, "allow_skip": false, "target_paths": [{"path": "UI/Buy_Ascend/Sat_left_select", "status": "Tap SELECT to equip."}, {"path": "UI/Buy_Ascend/Sat_right_select", "status": "Tap SELECT to equip."}, {"path": "UI/Buy_Ascend/Selected", "status": "Tap SELECT to equip."}, {"path": "UI/Bottom_ui/Bottom/HBoxContainer/Back", "status": "Tap BACK."}]}

## Called by the shop right after a satellite purchase succeeds.
func notify_satellite_purchased() -> void:
	if get_campaign_stage() != "shop_satellite_upgrade":
		return
	_set_stage("shop_satellite_equip")
	_clear_overlay(true)
	_show_step("shop_satellite_equip", _shop_satellite_equip_step_def())

## Called by the shop once the satellite is actually equipped.
func notify_satellite_equipped() -> void:
	if get_campaign_stage() != "shop_satellite_equip":
		return
	_set_stage("shop_exit")
	_clear_overlay(true)
	_show_step("shop_exit", {"text": "Satellite equipped. Leave the Ship Bay and begin Level 1.", "status": "Tap BACK.", "completion": "external", "allow_player_input": true, "dim_amount": 0.35, "allow_skip": false, "target_path": "UI/Bottom_ui/Bottom/HBoxContainer/Back"})

func notify_satellite_upgraded() -> void:
	if get_campaign_stage() != "shop_satellite_upgrade" and get_campaign_stage() != "shop_satellite_equip":
		return
	_set_stage("shop_exit")
	_clear_overlay(true)
	_show_step("shop_exit", {"text": "Satellite equipped. Leave the Ship Bay and begin Level 1.", "status": "Tap BACK.", "completion": "external", "allow_player_input": true, "dim_amount": 0.35, "allow_skip": false, "target_path": "UI/Bottom_ui/Bottom/HBoxContainer/Back"})

func notify_shop_exited() -> void:
	if get_campaign_stage() == "shop_exit":
		_set_stage("level1_entry")
	_clear_overlay(true)

func notify_level_selected(level_num: int) -> void:
	if level_num == 1 and get_campaign_stage() == "level1_entry":
		_set_stage("level1_playing")
		_clear_overlay(true)

func start_level_one() -> void:
	if get_campaign_stage() == "level1_playing":
		_show_step("level1_start", {"text": "This is the real fight now. Use what you learned and clear the sector.", "status": "Tap NEXT to begin.", "completion": "continue", "allow_player_input": false, "dim_amount": 0.42, "allow_skip": false})

func complete_level_one() -> bool:
	if int(GameManager.get_current_level()) != 1 or get_campaign_stage() != "level1_playing":
		return false
	_set_stage("wheel_intro")
	_clear_overlay(true)
	GameManager.level_manager.complete_level(1)
	GameManager.change_scene("res://MainScenes/Intern_Menu.tscn")
	return true

func on_intern_menu_ready(menu: Node) -> void:
	if get_campaign_stage() != "wheel_intro":
		return
	_show_step("wheel_intro", {"text": "Fortune Wheel unlocked. Claim a reward, then the galaxy is yours to explore.", "status": "Tap NEXT to open it.", "completion": "continue", "next_stage": STAGE_COMPLETE, "allow_player_input": false, "dim_amount": 0.5, "allow_skip": false, "open_wheel": menu})

func begin_shadow_unlock_flow() -> bool:
	if not is_new_player_campaign_active():
		return false
	_set_stage("shadow_map_intro")
	GameManager.change_scene(GameManager.get_map_scene_path())
	return true

func start_shadow_level_six() -> void:
	if get_campaign_stage() == "shadow_charge_explained":
		_show_step("shadow_level6", {"text": "Destroy enemies to charge Shadow Drive. When the gauge reads READY, we will activate it together.", "status": "Tap NEXT, then fill the gauge.", "completion": "continue", "allow_player_input": false, "dim_amount": 0.46, "allow_skip": false})

func notify_shadow_ready() -> void:
	if get_campaign_stage() != "shadow_charge_explained" or not _active_id.is_empty():
		return
	_show_step("shadow_ready", {"text": "Shadow Drive is charged. Tap the READY gauge now to engage Shadow Mode.", "status": "Tap NEXT, then tap READY.", "completion": "continue", "allow_player_input": false, "dim_amount": 0.5, "allow_skip": false, "slow_motion": true})

func _ready() -> void:
	if not GameManager.shadow_mode_activated.is_connected(_on_shadow_mode_activated):
		GameManager.shadow_mode_activated.connect(_on_shadow_mode_activated)
	_validate_tutorial_state()

func _on_shadow_mode_activated() -> void:
	if get_campaign_stage() == "shadow_charge_explained" and int(GameManager.get_current_level()) == 6:
		_set_stage("shadow_activated")
		SaveManager.mark_tutorial_completed(SHADOW_MODE_ID)

func notify_overclock_reached() -> void:
	if SaveManager.get_tutorial_flag("overclock_explained") or not _active_id.is_empty():
		return
	_show_step("overclock", {"text": "Overclock limit reached. Your weapon damage is now capped; extra power cores are converted into score.", "status": "Tap NEXT to continue.", "completion": "continue", "allow_player_input": false, "dim_amount": 0.45, "allow_skip": true, "mark_flag": "overclock_explained"})

func start_core_onboarding() -> bool:
	return start_level_zero()

func start_shadow_mode_tutorial() -> bool:
	return begin_shadow_unlock_flow()

## --- Progress tracking ---

const _LEVEL_ZERO_STEPS: Array[String] = [
	"level0_intro", "level0_bullet", "level0_coin",
	"level0_powerup", "level0_revive",
]

const _LEVEL_ZERO_TOTAL := 5

func _inject_progress(step: Dictionary, id: String) -> void:
	var idx := _LEVEL_ZERO_STEPS.find(id)
	if idx >= 0:
		step["step_index"] = idx + 1
		step["total_steps"] = _LEVEL_ZERO_TOTAL

func _show_step(id: String, step: Dictionary) -> bool:
	# If we're stuck in a clearing state from a scene change, force-reset.
	if _clearing:
		_clearing = false
	if not _active_id.is_empty():
		# Self-heal: a scene change can free the old overlay without a formal
		# _clear_overlay (e.g. tapping SHOP swaps scenes directly). If the old
		# overlay is gone from the tree, the step is dead — clear and continue.
		if _overlay == null or not is_instance_valid(_overlay) or not _overlay.is_inside_tree():
			_active_id = ""
			_active_step.clear()
			if _tutorial_layer != null and is_instance_valid(_tutorial_layer):
				_tutorial_layer.queue_free()
			_tutorial_layer = null
			_overlay = null
		else:
			return false
	var current_scene: Node = get_tree().current_scene
	if not is_instance_valid(current_scene):
		return false
	_active_id = id
	_active_step = step.duplicate(true)
	_inject_progress(_active_step, id)
	_tutorial_layer = CanvasLayer.new()
	_tutorial_layer.layer = 100
	_tutorial_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = TUTORIAL_OVERLAY.instantiate() as TutorialOverlay
	_tutorial_layer.add_child(_overlay)
	current_scene.add_child(_tutorial_layer)
	_overlay.continue_requested.connect(_advance_active_step)
	_overlay.skip_requested.connect(_skip_active_step)
	if bool(_active_step.get("slow_motion", false)):
		_set_slow_motion(true)
	_set_player_input_enabled(bool(_active_step.get("allow_player_input", true)))
	_overlay.present_step(_active_step, _get_guide_portrait())
	return true

func _advance_active_step() -> void:
	if _active_id.is_empty() or str(_active_step.get("completion", "continue")) != "continue":
		return
	var next_stage: String = str(_active_step.get("next_stage", ""))
	var mark_flag: String = str(_active_step.get("mark_flag", ""))
	var wheel_menu: Node = _active_step.get("open_wheel", null) as Node
	if not mark_flag.is_empty():
		SaveManager.set_tutorial_flag(mark_flag)
	_clear_overlay(true)
	if is_instance_valid(wheel_menu) and wheel_menu.has_node("Wheel"):
		var wheel: Node = wheel_menu.get_node("Wheel")
		if wheel.has_method("popup_open"):
			wheel.call("popup_open")
	# If there is a chained next_stage, show that step after a brief delay
	# so the fade-out completes before the new overlay appears.
	if not next_stage.is_empty():
		_set_stage(next_stage)
		call_deferred("_show_chained_step", next_stage)

func _skip_active_step() -> void:
	if bool(_active_step.get("allow_skip", true)):
		_advance_active_step()

func _set_stage(stage: String) -> void:
	if SaveManager and SaveManager.has_method("set_tutorial_campaign_stage"):
		SaveManager.set_tutorial_campaign_stage(stage)
		GameManager.save_progress_if_enabled()

## Shows the next chained step in a sequence. Called via call_deferred
## after _clear_overlay so the fade-out has time to finish.
func _show_chained_step(stage: String) -> void:
	match stage:
		"level0_bullet":
			_show_step("level0_bullet", {
				"text": "Hostile fire detected. Enemy bullets can destroy your fighter. Keep moving and do not fly into their path.",
				"status": "Tap NEXT.", "completion": "continue", "next_stage": "level0_coin",
				"allow_player_input": false, "dim_amount": 0.58, "allow_skip": false
			})
		"level0_coin":
			_show_step("level0_coin", {
				"text": "Collect coins to fund permanent ship upgrades between missions.",
				"status": "Tap NEXT.", "completion": "continue", "next_stage": "level0_powerup",
				"allow_player_input": false, "dim_amount": 0.48, "allow_skip": false
			})
		"shop_upgrade":
			# Reached when the player taps NEXT on the payout reveal.
			_show_step("shop_upgrade", _shop_upgrade_step_def())
		"level0_powerup":
			_show_step("level0_powerup", {
				"text": "Collect power cores to increase your firepower during this mission.",
				"status": "Tap NEXT to begin combat.", "completion": "continue", "next_stage": "level0_combat",
				"allow_player_input": false, "dim_amount": 0.48, "allow_skip": false
			})

func _set_player_input_enabled(enabled: bool) -> void:
	var player: Node = get_tree().get_first_node_in_group("Player")
	if player and "input_enabled" in player:
		player.input_enabled = enabled

func _set_slow_motion(enabled: bool) -> void:
	if enabled and not _slow_motion_active:
		_previous_time_scale = Engine.time_scale
		Engine.time_scale = 0.18
		_slow_motion_active = true
	elif not enabled and _slow_motion_active:
		Engine.time_scale = _previous_time_scale
		_slow_motion_active = false

func _clear_overlay(enable_player_input: bool) -> void:
	_set_slow_motion(false)
	if enable_player_input:
		_set_player_input_enabled(true)
	var layer_to_free: CanvasLayer = _tutorial_layer
	var overlay_to_dismiss: TutorialOverlay = _overlay
	_active_id = ""
	_active_step.clear()
	_tutorial_layer = null
	_overlay = null
	_clearing = true
	if is_instance_valid(overlay_to_dismiss) and is_instance_valid(layer_to_free):
		overlay_to_dismiss.continue_requested.disconnect(_advance_active_step)
		overlay_to_dismiss.skip_requested.disconnect(_skip_active_step)
		overlay_to_dismiss.dismissed.connect(_free_layer.bind(layer_to_free), CONNECT_ONE_SHOT)
		overlay_to_dismiss.fade_out_and_dismiss()
	elif is_instance_valid(layer_to_free):
		layer_to_free.queue_free()
		_clearing = false

func _free_layer(layer: CanvasLayer) -> void:
	if is_instance_valid(layer):
		layer.queue_free()
	_clearing = false

## --- Startup recovery ---

const _IN_PROGRESS_LEVEL_STAGES: Array[String] = [
	"level0_intro", "level0_bullet",
	"level0_coin", "level0_powerup", "level0_combat",
	"level0_revive",
]

const _IN_PROGRESS_MAP_STAGES: Array[String] = [
	"shop_entry", "shop_upgrade", "shop_satellite_tab", "shop_satellite_upgrade", "shop_exit",
	"level1_entry", "level1_playing", "wheel_intro",
	"shadow_map_intro", "shadow_charge_explained", "shadow_activated",
]

func _is_in_progress_level_stage(stage: String) -> bool:
	return stage in _IN_PROGRESS_LEVEL_STAGES

func _validate_tutorial_state() -> void:
	# Reset slow motion that may have been left active from a previous session.
	if _slow_motion_active:
		_set_slow_motion(false)
	
	var stage := get_campaign_stage()
	if stage == STAGE_COMPLETE:
		return
	
	if not is_new_player_campaign_active():
		return
	
	# Stuck mid-level tutorial — reset to the start of the level flow so
	# the tutorial can replay cleanly from the beginning.
	if _is_in_progress_level_stage(stage) and stage != "level0_intro":
		_set_stage("level0_intro")
	
	# Stuck mid-shop or mid-gameplay tutorial — reset to shop entry.
	if stage in _IN_PROGRESS_MAP_STAGES and stage != "shop_entry":
		_set_stage("shop_entry")

func _get_guide_portrait() -> Texture2D:
	return load("res://Assets/UI/Tutorial/Commander.png") as Texture2D
