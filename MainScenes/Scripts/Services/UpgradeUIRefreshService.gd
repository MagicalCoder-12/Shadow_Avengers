extends RefCounted
class_name UpgradeUIRefreshService

func format_number(num: int) -> String:
	if num >= 1000000000:
		return "%.1fB" % (num / 1000000000.0)
	elif num >= 1000000:
		return "%.1fM" % (num / 1000000.0)
	elif num >= 1000:
		return "%.1fK" % (num / 1000.0)
	return str(num)

func update_currency_display(game_manager, crystals_label: Label, coins_label: Label, void_shards_label: Label) -> bool:
	if not crystals_label:
		push_error("Crystals_display node is null!")
		return false
	if not coins_label:
		push_error("Coins_display node is null!")
		return false
	if not void_shards_label:
		push_error("void_shards_display node is null!")
		return false
	if not game_manager:
		push_error("GameManager is null!")
		return false

	var crystals_text := format_number(int(game_manager.crystal_count))
	var coins_text := format_number(int(game_manager.coin_count))
	var void_shards_text := format_number(int(game_manager.void_shards_count))

	crystals_label.text = "Crystals: %s" % crystals_text
	coins_label.text = "Coins: %s" % coins_text
	void_shards_label.text = "Void Shards: %s" % void_shards_text
	return true

func is_currency_display_stale(game_manager, crystals_label: Label, coins_label: Label, void_shards_label: Label) -> bool:
	if not game_manager or not crystals_label or not coins_label or not void_shards_label:
		return true

	var expected_crystals := "Crystals: %s" % format_number(int(game_manager.crystal_count))
	var expected_coins := "Coins: %s" % format_number(int(game_manager.coin_count))
	var expected_void_shards := "Void Shards: %s" % format_number(int(game_manager.void_shards_count))

	return crystals_label.text != expected_crystals \
		or coins_label.text != expected_coins \
		or void_shards_label.text != expected_void_shards

func get_ship_texture_dynamic(ship: Dictionary, evolution_stage: int) -> Texture2D:
	if not ship.has("textures"):
		push_error("No textures found for ship: %s" % ship.get("display_name", "Unknown"))
		return null

	var textures = ship["textures"]
	if textures.is_empty():
		push_error("Textures dictionary is empty for ship: %s" % ship.get("display_name", "Unknown"))
		return null

	var texture_key = "base" if evolution_stage == 0 else "upgrade_%d" % evolution_stage
	var texture_path = textures.get(texture_key, textures.get("base", ""))

	if not texture_path:
		push_warning("Texture key %s not found for %s, using fallback" % [texture_key, ship.get("display_name", "Unknown")])
		return null

	return load(texture_path)

func get_satellite_texture_dynamic(satellite: Dictionary) -> Texture2D:
	if not satellite.has("texture"):
		push_error("No texture found for satellite: %s" % satellite.get("display_name", "Unknown"))
		return null

	var texture_path = satellite["texture"]
	if not texture_path:
		push_warning("Texture path is empty for satellite: %s" % satellite.get("display_name", "Unknown"))
		return null

	return load(texture_path)

func update_all_ship_textures(game_manager, ship_textures_ui: Array) -> void:
	if not game_manager:
		return
	if ship_textures_ui.size() != game_manager.ships.size():
		push_warning("Mismatch: ship_textures_ui has %d elements, but ships has %d" %
			[ship_textures_ui.size(), game_manager.ships.size()])

	for i in range(min(game_manager.ships.size(), ship_textures_ui.size())):
		var ship = game_manager.ships[i]
		var texture_node = ship_textures_ui[i]

		if not texture_node:
			push_warning("Texture node at index %d is null!" % i)
			continue

		var current_texture = get_ship_texture_dynamic(ship, int(ship.get("current_evolution_stage", 0)))
		if current_texture:
			texture_node.texture = current_texture
			texture_node.modulate = Color.WHITE if bool(ship.get("unlocked", false)) else Color.BLACK

func update_all_satellite_textures(game_manager, satellite_textures_ui: Array) -> void:
	if not game_manager:
		return
	if satellite_textures_ui.size() != game_manager.satellites.size():
		push_warning("Mismatch: satellite_textures_ui has %d elements, but satellites has %d" %
			[satellite_textures_ui.size(), game_manager.satellites.size()])

	for i in range(min(game_manager.satellites.size(), satellite_textures_ui.size())):
		var satellite = game_manager.satellites[i]
		var texture_node = satellite_textures_ui[i]

		if not texture_node:
			push_warning("Texture node at index %d is null!" % i)
			continue

		var current_texture = get_satellite_texture_dynamic(satellite)
		if current_texture:
			texture_node.texture = current_texture
			texture_node.modulate = Color.WHITE if bool(satellite.get("unlocked", false)) else Color.BLACK

func optimize_texture_loading(game_manager, ship_textures_ui: Array, selected_ship_index: int) -> void:
	if not game_manager:
		return
	var visible_ships = [selected_ship_index]
	for i in range(maxi(0, selected_ship_index - 2), min(game_manager.ships.size(), selected_ship_index + 3)):
		if i != selected_ship_index:
			visible_ships.append(i)

	for ship_index in visible_ships:
		if ship_index < 0 or ship_index >= game_manager.ships.size():
			continue
		var ship = game_manager.ships[ship_index]
		var texture_node = ship_textures_ui[ship_index]
		if texture_node:
			var current_texture = get_ship_texture_dynamic(ship, int(ship.get("current_evolution_stage", 0)))
			if current_texture:
				texture_node.texture = current_texture

func update_current_satellite_textures(game_manager) -> void:
	if not game_manager:
		return
	var tree = game_manager.get_tree()
	if not tree:
		return
	var current_scene = tree.current_scene
	if not current_scene:
		return

	var satellites = current_scene.get_nodes_in_group("Satellite")
	for satellite in satellites:
		if satellite and satellite.has_method("_load_satellite_data"):
			satellite._load_satellite_data()
			if GameManager.debug_mode:
				print("Updated satellite texture for: ", satellite.name)

	var player = current_scene.get_node_or_null("Player")
	if not player:
		var players = current_scene.get_nodes_in_group("Player")
		if players.size() > 0:
			player = players[0]

	if player:
		var player_sprite = player.get_node_or_null("Sprite2D")
		if player_sprite:
			for child in player_sprite.get_children():
				if child.name.begins_with("Satellite") and child.has_method("_load_satellite_data"):
					child._load_satellite_data()
					if GameManager.debug_mode:
						print("Updated satellite texture for: ", child.name)

	await tree.process_frame
	for satellite in satellites:
		if satellite and satellite.has_method("_load_satellite_data"):
			satellite._load_satellite_data()
