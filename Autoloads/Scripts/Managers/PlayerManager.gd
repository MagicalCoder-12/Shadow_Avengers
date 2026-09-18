extends Node


var gm: Node
var default_ship_id: String = "Ship1"
var selected_ship_id: String
var _reviving: bool = false  # Prevent re-entry during await
var selected_satellite_ids: Array[String] = []  # Array of selected satellite IDs
const DEFAULT_SATELLITE_ID: String = "Satellite1"
var player_spawn_position: Vector2 = Vector2.ZERO
var default_bullet_speed: float = 3000.0
var default_bullet_damage: int = 20
var max_attack_level: int = 4
var player_stats: Dictionary

func _ready() -> void:
	gm = GameManager
	# Defer initialization until all autoloads are ready
	call_deferred("initialize")

func initialize() -> void:
	_load_settings_from_config()
	_initialize_player_stats()
	# Only set default ship ID if no ship ID was loaded from save data
	if selected_ship_id.is_empty():
		selected_ship_id = default_ship_id
	set_spawn_position()

func _load_settings_from_config() -> void:
	# Read settings via GameManager helpers so config access is centralized.
	if gm:
		default_bullet_speed = gm.get_game_setting("default_bullet_speed", 3000.0)
		default_bullet_damage = gm.get_game_setting("default_bullet_damage", 20)
		max_attack_level = gm.get_game_setting("max_attack_level", 4)

	# Add max_life loading
	@warning_ignore("unused_variable")
	var max_life_setting = gm.get_player_setting("max_life", 3) if gm else 3
	
	# We'll need to make this accessible to the Player class
	# For now, we'll just note that we've loaded it

	# Use a copied ships list from GameManager to avoid mutating shared config data.
	var ships_data: Array = gm.get_config_ships_data() if gm else []
	if not ships_data.is_empty():
		default_ship_id = ships_data[0].id
	else:
		push_error("Ships data is empty, cannot determine default ship ID.")
		default_ship_id = "Ship1"

func _initialize_player_stats() -> void:
	player_stats = {
		"attack_level": 0,
		"bullet_damage": default_bullet_damage,
		"base_bullet_damage": default_bullet_damage,
		"is_shadow_mode_active": false,
		"is_super_mode_active": false
	}
	# Initialize satellite selection - default to first two available satellites
	if selected_satellite_ids.is_empty():
		selected_satellite_ids.resize(2)
		selected_satellite_ids[0] = DEFAULT_SATELLITE_ID  # Default left satellite
		selected_satellite_ids[1] = DEFAULT_SATELLITE_ID  # Default right satellite
	sanitize_selected_satellite_ids()

func _is_satellite_unlocked(satellite_id: String) -> bool:
	if not gm or not (gm.satellites is Array):
		return satellite_id == DEFAULT_SATELLITE_ID
	for satellite in gm.satellites:
		if not (satellite is Dictionary):
			continue
		if str(satellite.get("id", "")) == satellite_id:
			return bool(satellite.get("unlocked", false))
	return false

# Ensure both satellite slots always resolve to unlocked IDs.
func sanitize_selected_satellite_ids() -> void:
	if selected_satellite_ids.size() < 2:
		selected_satellite_ids.resize(2)
	for i in range(2):
		var candidate: String = str(selected_satellite_ids[i]) if i < selected_satellite_ids.size() else ""
		if candidate.is_empty() or not _is_satellite_unlocked(candidate):
			selected_satellite_ids[i] = DEFAULT_SATELLITE_ID

func get_selected_satellite_id(slot_index: int) -> String:
	sanitize_selected_satellite_ids()
	if slot_index >= 0 and slot_index < selected_satellite_ids.size():
		return selected_satellite_ids[slot_index]
	return DEFAULT_SATELLITE_ID

func save_player_stats(attack_level: int, bullet_damage: int, base_bullet_damage: int, is_shadow_mode_active: bool, is_super_mode_active: bool = false) -> void:
	player_stats["attack_level"] = attack_level
	player_stats["bullet_damage"] = bullet_damage
	player_stats["base_bullet_damage"] = base_bullet_damage
	player_stats["is_shadow_mode_active"] = is_shadow_mode_active
	player_stats["is_super_mode_active"] = is_super_mode_active

func restore_player_stats(player: Node) -> void:
	if not player or not player.has_method("set_stats"):
		push_error("Cannot restore stats: Invalid player node")
		return

	player.set_stats(
		player_stats["attack_level"],
		player_stats["bullet_damage"],
		player_stats["base_bullet_damage"],
		player_stats["is_shadow_mode_active"],
		false  # Always restore with super mode deactivated
	)
	
	# Ensure super mode is properly deactivated on revival
	player_stats["is_super_mode_active"] = false

func set_spawn_position() -> void:
	var viewport_size: Vector2 = gm.get_viewport().get_visible_rect().size
	player_spawn_position = Vector2(viewport_size.x / 2, viewport_size.y)

func spawn_player(lives: int, apply_revive_state: bool = false) -> void:
	var current_scene = gm.get_tree().current_scene
	if not current_scene:
		return

	var player_scene_path = "res://Ships/Player_%s.tscn" % selected_ship_id
	if ResourceLoader.exists(player_scene_path):
		var player_scene = load(player_scene_path)
		var player_instance = player_scene.instantiate()
		player_instance.global_position = player_spawn_position
		current_scene.call_deferred("add_child", player_instance)
		if apply_revive_state:
			# Ensure fresh-spawn revives receive invincibility/shield behavior.
			player_instance.call_deferred("revive", lives)
		else:
			player_instance.call_deferred("set_lives", lives)
	else:
		push_error("[DEBUG] Player scene not found at path: %s" % player_scene_path)

# Keep revive default at one life to match game-over revive UI expectations.
func revive_player(lives: int = 1) -> void:
	# Guard against re-entry during the await at the end.
	if _reviving:
		return
	_reviving = true

	# Always reset the ad manager's revive pending state to prevent double revives
	gm.reset_ad_revive_state()

	gm.request_game_over_clear("PlayerManager.revive_player")
	gm.is_paused = false
	gm.get_tree().paused = false

	gm.player_lives = lives
	gm.on_player_life_changed.emit(gm.player_lives)

	set_spawn_position()

	gm.save_progress_if_enabled()

	AudioManager.mute_bus("Bullet", false)
	AudioManager.mute_bus("Explosion", false)

	var current_scene = gm.get_tree().current_scene
	var player_found = false

	if current_scene:
		_hide_game_over_screen(current_scene)

	for player in gm.get_tree().get_nodes_in_group("Player"):
		if player.ship_id == selected_ship_id:
			player.revive(lives)
			player_found = true
			break

	if not player_found:
		spawn_player(lives, true)

	gm.set_level_game_over_screen_active(false)

	# Hide banner ad when reviving player to prevent conflicts
	gm.hide_banner_ad_if_initialized()
	# Small delay before banner ad can be shown again.
	await gm.get_tree().create_timer(1.0).timeout
	_reviving = false


func _hide_game_over_screen(current_scene: Node) -> void:
	var found = false
	for child in current_scene.get_children():
		if child.name == "GameOverScreen":
			child.visible = false
			found = true
			break

	if not found:
		for child in current_scene.get_children():
			if child is CanvasLayer:
				for subchild in child.get_children():
					if subchild.name == "GameOverScreen":
						subchild.visible = false
						found = true
						break
				if found:
					break

	if not found:
		push_warning("GameOverScreen not found in current scene")

func reset_player_stats() -> void:
	player_stats = {
		"attack_level": 0,
		"bullet_damage": default_bullet_damage,
		"base_bullet_damage": default_bullet_damage,
		"is_shadow_mode_active": false,
		"is_super_mode_active": false
	}


# Update damage for the currently selected ship
func update_current_ship_damage(new_damage: int) -> void:
	player_stats["base_bullet_damage"] = new_damage
	# If not in shadow mode or super mode, also update current bullet damage
	if not player_stats.get("is_shadow_mode_active", false) and not player_stats.get("is_super_mode_active", false):
		player_stats["bullet_damage"] = new_damage


# Update satellite selection and textures in the current scene
func update_selected_satellites() -> void:
	sanitize_selected_satellite_ids()
	# Find the current player in the scene and update its satellites
	var players = gm.get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		var player = players[0]
		
		# Call the player's method to update satellites from selection
		if player and player.has_method("update_satellites_from_selection"):
			player.update_satellites_from_selection()
	
	# Also emit a signal so all players can update their satellites if needed
	gm.player_manager_satellites_changed.emit()


# Signal handler for when satellite selections change
func _on_player_manager_satellites_changed() -> void:
	# This method will be called when satellite selections change
	sanitize_selected_satellite_ids()
	# Find all players and update their satellites
	var players = gm.get_tree().get_nodes_in_group("Player")
	for player in players:
		if player and player.has_method("update_satellites_from_selection"):
			player.update_satellites_from_selection()
