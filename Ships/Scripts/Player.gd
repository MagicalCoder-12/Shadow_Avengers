extends Area2D
class_name Player

@warning_ignore("unused_signal")
signal victory_pose_done()

# Preloaded scenes
var plBullet: PackedScene = preload("res://Bullet/PlBullet/Bullet.tscn")
var plSuperBullet: PackedScene = preload("res://Bullet/PlBullet/super_bullet.tscn")
var plShadowBullet: PackedScene = preload("res://Bullet/PlBullet/plshadow_bullet.tscn")
var plNormalBullet: PackedScene = preload("res://Bullet/PlBullet/Bullet.tscn")  # Store reference to ship's normal bullet
# Node references
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var firing_positions: Node2D = $Sprite2D/FiringPositions
@onready var fire_delay_timer: Timer = $FireDelayTimer
@onready var invincibility_timer: Timer = $InvincibilityTimer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var death_animation: CPUParticles2D = $DeathAnimation
@onready var power_up_notification: Label = $PowerUpNotification
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var revive_shiled: Sprite2D = $Revive_shiled

# Exported variables
@export var ship_id: String = ""  # Unique identifier for the ship
@export var speed: float = 2000.0
@export var touch_speed: float = 500.0
@export var smoothness: float = 0.3
@export var normal_fire_delay: float = 0.3
@export var boundary_padding: float = 10.0
@export var max_life: int = 3
@export var shadow_speed_multiplier: float = 1.2
@export var shadow_fire_delay_multiplier: float = 0.1
@export var spread_angle_increment: float = 10.0
@export var spawn_point_offset: float = 5.0
@export var super_mode_damage_boost: int = 2
@export var super_mode_speed_multiplier: float = 2.0
@export var super_mode_fire_delay: float = 0.15
@export var super_mode_bullet_speed: float = 5000.0
@export var shadow_bullet_count: int = 25
@export var base_bullet_damage: int = 20
@export var shadow_texture: Texture2D = preload("res://Assets/player/g-02.png")
@export var evolution_textures: Array[Texture2D] = []  # Textures for each evolution stage

# Local variables
var is_alive: bool = true
var death_in_progress: bool = false
var lives: int = 3  # Synced with GameManager
var original_texture: Texture2D
var original_speed: float
var laser_shoot_sfx: AudioStream = preload("res://Assets/Music/Laser_Shoot16.wav")
var super_mode_timer: Timer
var input_enabled: bool = true
const REVIVE_INVINCIBILITY_DURATION: float = 4.0
const DAMAGE_INVINCIBILITY_DURATION: float = 2.5
var revive_service: PlayerReviveService = PlayerReviveService.new()
var combat_service: PlayerCombatService = PlayerCombatService.new()
var mode_service: PlayerModeService = PlayerModeService.new()
var movement_input_service: PlayerMovementInputService = PlayerMovementInputService.new()
var satellite_service: PlayerSatelliteService = PlayerSatelliteService.new()

func _remove_all_satellites() -> void:
	satellite_service.remove_all_satellites()

func _ready() -> void:
	_initialize_player()
	_setup_references()
	_connect_signals()
	_apply_initial_state()
	_initialize_satellites()

func _initialize_player() -> void:
	# Sync lives with GameManager
	lives = GameManager.player_lives
	GameManager.save_progress_if_enabled()

	sprite_2d.show()
	# Cache original speed
	original_speed = speed

	# Set ship_id and apply stats and texture from PlayerManager
	ship_id = GameManager.player_manager.selected_ship_id
	_apply_ship_stats()
	_debug_log("Player initialized with ship_id: " + ship_id)

	# Add to Player group
	add_to_group("Player")

	if revive_shiled:
		revive_shiled.visible = false

	# Initialize ship-specific base stats
	GameManager.player_manager.player_stats["base_bullet_damage"] = base_bullet_damage
	GameManager.player_manager.player_stats["bullet_damage"] = base_bullet_damage

	# Ensure we have the latest upgraded damage if available
	var current_ship_damage = GameManager.player_manager.player_stats.get("base_bullet_damage", base_bullet_damage)
	if current_ship_damage != base_bullet_damage:
		base_bullet_damage = current_ship_damage
		_debug_log("Synchronized damage to upgraded value: %d" % base_bullet_damage)

func _apply_ship_stats() -> void:
	# Find the ship configuration in GameManager.ships and apply stats and texture
	for ship in GameManager.ships:
		if ship.get("id", "") == ship_id:  # Compare with id instead of display_name
			base_bullet_damage = ship.get("damage", base_bullet_damage)
			var stage = ship.get("current_evolution_stage", 0)
			if stage < evolution_textures.size() and evolution_textures[stage]:
				sprite_2d.texture = evolution_textures[stage]
				original_texture = evolution_textures[stage]
			else:
				push_warning("No texture for stage %d of %s" % [stage, ship_id])
			_debug_log("Applied ship stats and texture for %s: speed=%s, damage=%s, stage=%d" % [ship_id, speed, base_bullet_damage, stage])
			return
	_debug_log("Warning: No ship configuration found for ship_id: " + ship_id + ". Using default stats and texture.")

func _setup_references() -> void:
	# Validate node references
	if not death_animation:
		push_warning("DeathAnimation node is missing or not properly set up")
	if not invincibility_timer:
		push_error("InvincibilityTimer node is missing in Player.tscn")
	revive_service.configure(self, invincibility_timer, animation_player, revive_shiled, sprite_2d, self)
	if not plBullet or not plBullet.can_instantiate():
		push_error("Invalid plBullet scene")
	if not plSuperBullet or not plSuperBullet.can_instantiate():
		push_error("Invalid plSuperBullet scene")
	if not plShadowBullet or not plShadowBullet.can_instantiate():
		push_error("Invalid plShadowBullet scene")
	# Set up super mode timer
	super_mode_timer = Timer.new()
	super_mode_timer.name = "SuperModeTimer"
	super_mode_timer.one_shot = true
	add_child(super_mode_timer)
	super_mode_timer.timeout.connect(_on_super_mode_timeout)
	mode_service.configure(
		self,
		GameManager,
		sprite_2d,
		fire_delay_timer,
		firing_positions,
		super_mode_timer,
		ship_id,
		shadow_texture,
		original_texture,
		original_speed,
		normal_fire_delay,
		shadow_speed_multiplier,
		shadow_fire_delay_multiplier,
		super_mode_speed_multiplier,
		super_mode_damage_boost,
		super_mode_fire_delay,
		spawn_point_offset,
		plNormalBullet,
		plSuperBullet,
		plShadowBullet,
		GameManager.get_game_settings_section("player_balance")
	)
	movement_input_service.configure(self, collision_shape, smoothness, boundary_padding)
	satellite_service.configure(self, sprite_2d, GameManager, Callable(self, "_debug_log"))
	_ensure_damage_collision_mask()

func _ensure_damage_collision_mask() -> void:
	if not has_method("set_collision_mask_value"):
		return

	for layer in [2, 3, 4, 6, 7, 8]:
		set_collision_mask_value(layer, true)

func _connect_signals() -> void:
	# Connect to LevelManager
	var level_manager = get_tree().get_first_node_in_group("LevelManager")
	if level_manager:
		if level_manager.has_signal("Victory_pose"):
			level_manager.Victory_pose.connect(_on_victory_pose)
		else:
			_debug_log("LevelManager does not have Victory_pose signal")

	# Connect to Level node
	var level_node = get_tree().get_first_node_in_group("Level")
	if level_node and level_node.has_signal("Victory_pose"):
		level_node.Victory_pose.connect(_on_victory_pose)
	else:
		# Try to find the Level node by name if not in group
		level_node = get_parent()
		while level_node and not (level_node is Node and level_node.has_signal("Victory_pose")):
			level_node = level_node.get_parent()
			if level_node == null:
				break

		if level_node and level_node.has_signal("Victory_pose"):
			level_node.Victory_pose.connect(_on_victory_pose)
			_debug_log("Connected to Level node by hierarchy traversal")
		else:
			_debug_log("Could not find Level node with Victory_pose signal")

	# Connect GameManager signals
	GameManager.on_player_life_changed.connect(_on_player_life_changed)
	GameManager.game_over_triggered.connect(_on_game_over_triggered)
	GameManager.shadow_mode_activated.connect(_on_shadow_mode_activated)
	GameManager.shadow_mode_deactivated.connect(_on_shadow_mode_deactivated)
	GameManager.level_completed.connect(_on_level_completed)
	GameManager.ship_stats_updated.connect(_on_ship_stats_updated)
	GameManager.satellite_stats_updated.connect(_on_satellite_stats_updated)
	GameManager.player_manager_satellites_changed.connect(_on_player_manager_satellites_changed)

func _apply_initial_state() -> void:
	# Apply shadow mode if enabled
	if GameManager.is_shadow_mode_enabled():
		_on_shadow_mode_activated()

func _initialize_satellites() -> void:
	satellite_service.initialize_satellites()

func _debug_log(message: String) -> void:
	if GameManager.debug_mode:
		print("[Player Debug] " + message)

func update_satellites_from_selection() -> void:
	satellite_service.update_satellites_from_selection()

func _on_satellite_stats_updated(satellite_id: String, damage_bonus: int) -> void:
	satellite_service.on_satellite_stats_updated(satellite_id, damage_bonus)

func _process(_delta: float) -> void:
	if is_alive and fire_delay_timer.is_stopped():
		shoot()

func _physics_process(delta: float) -> void:
	if not input_enabled:
		return
	handle_keyboard_movement(delta)
	if movement_input_service.is_touching:
		handle_touch_movement()
	clamp_position()

func _input(event: InputEvent) -> void:
	movement_input_service.handle_input(event, input_enabled)

func get_health_percent() -> float:
	return float(lives) / float(max_life)

func _on_shadow_mode_activated() -> void:
	if mode_service.is_shadow_mode_active():
		return
	mode_service.set_shadow_mode_active(true)
	apply_shadow_mode_effects()

func _on_shadow_mode_deactivated() -> void:
	mode_service.set_shadow_mode_active(false)
	revert_shadow_mode_effects()

func apply_shadow_mode_effects() -> void:
	mode_service.apply_shadow_mode_effects()

func revert_shadow_mode_effects() -> void:
	mode_service.revert_shadow_mode_effects()

func shoot() -> void:
	fire_delay_timer.start(mode_service.get_balanced_fire_delay(fire_delay_timer.wait_time))
	var is_super_mode = GameManager.player_manager.player_stats.get("is_super_mode_active", false)
	var is_shadow_mode = GameManager.player_manager.player_stats.get("is_shadow_mode_active", false)
	var bullet_damage: int = mode_service.get_balanced_bullet_damage(
		GameManager.player_manager.player_stats.get("bullet_damage", GameManager.player_manager.default_bullet_damage)
	)
	bullet_damage = GameManager.get_god_mode_damage(bullet_damage)

	# Check if this is Ship2 to apply swapped behavior
	if ship_id == "Ship2" and mode_service.use_ship2_mode_swap():
		# For Ship2, swap the bullet types and patterns
		if is_super_mode and not is_shadow_mode:
			# Super mode active: use shadow bullets with shadow pattern
			var bullet_scene: PackedScene = plShadowBullet
			var bullet_speed: float = GameManager.player_manager.default_bullet_speed
			_shoot_shadow_bullets(bullet_scene, bullet_speed, bullet_damage)
		elif is_shadow_mode and not is_super_mode:
			# Shadow mode active: use super bullets with super pattern
			var bullet_scene: PackedScene = plSuperBullet
			var bullet_speed: float = super_mode_bullet_speed
			_shoot_normal_bullets(bullet_scene, bullet_speed, bullet_damage)
		else:
			# Neither mode or both modes: use normal bullets with normal pattern
			var bullet_scene: PackedScene = plBullet
			var bullet_speed: float = GameManager.player_manager.default_bullet_speed
			_shoot_normal_bullets(bullet_scene, bullet_speed, bullet_damage)
	else:
		# For other ships, use standard behavior
		var bullet_scene: PackedScene = plSuperBullet if is_super_mode else plShadowBullet if is_shadow_mode else plBullet
		var bullet_speed: float = super_mode_bullet_speed if is_super_mode else GameManager.player_manager.default_bullet_speed

		if is_shadow_mode and not is_super_mode:
			_shoot_shadow_bullets(bullet_scene, bullet_speed, bullet_damage)
		else:
			_shoot_normal_bullets(bullet_scene, bullet_speed, bullet_damage)

	# Play shooting sound via AudioManager
	if AudioManager:
		AudioManager.play_sound_effect(laser_shoot_sfx, "Bullet")

func _shoot_shadow_bullets(bullet_scene: PackedScene, bullet_speed: float, bullet_damage: int) -> void:
	var angle_step: float = 360.0 / float(shadow_bullet_count)
	for i in range(shadow_bullet_count):
		var angle: float = deg_to_rad(i * angle_step)
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * spawn_point_offset
		var bullet: Node = BulletFactory.spawn_bullet(
			bullet_scene,
			global_position + offset,
			angle,
			bullet_speed,
			bullet_damage
		)
		if bullet:
			# Only add to scene if not already in the scene tree
			if not bullet.is_inside_tree():
				SceneSpawnService.spawn_child(bullet)

func _shoot_normal_bullets(bullet_scene: PackedScene, bullet_speed: float, bullet_damage: int) -> void:
	for child in firing_positions.get_children():
		var bullet: Node = BulletFactory.spawn_bullet(
			bullet_scene,
			child.global_position,
			child.rotation,
			bullet_speed,
			bullet_damage
		)
		if bullet:
			# Only add to scene if not already in the scene tree
			if not bullet.is_inside_tree():
				SceneSpawnService.spawn_child(bullet)

func handle_keyboard_movement(delta: float) -> void:
	movement_input_service.handle_keyboard_movement(delta, speed)

func handle_touch_movement() -> void:
	movement_input_service.handle_touch_movement()

func clamp_position() -> void:
	movement_input_service.clamp_position()

func damage(amount: int) -> void:
	if death_in_progress or combat_service.should_ignore_damage(revive_service, GameManager.player_manager.player_stats.get("is_shadow_mode_active", false), GameManager):
		return

	combat_service.save_current_stats(GameManager)
	# update_lives_after_damage writes GameManager.player_lives, whose setter
	# emits on_player_life_changed - handlers may legitimately change lives
	# during that signal (e.g. the tutorial auto-revive). GameManager is the
	# single source of truth, so read back instead of using the stale return.
	combat_service.update_lives_after_damage(GameManager, lives, amount)
	lives = GameManager.player_lives
	_debug_log("Player damaged, lives: " + str(lives))

	if lives > 0:
		combat_service.setup_damage_collision(self)
		revive_service.start_damage_invincibility(DAMAGE_INVINCIBILITY_DURATION)
		_play_death_animation()
		combat_service.handle_survival(self, sprite_2d, self)

func _play_death_animation() -> void:
	if death_animation:
		# Ensure one-shot particles can replay on every hit.
		death_animation.emitting = false
		death_animation.visible = true
		death_animation.restart()
		death_animation.emitting = true
	else:
		push_error("Cannot emit death animation: DeathAnimation is null")

func _handle_death() -> void:
	if TutorialManager.handle_tutorial_death(self):
		return
	if death_in_progress:
		return
	death_in_progress = true
	is_alive = false
	sprite_2d.visible = false
	_play_death_animation()

	var death_anim_duration: float = max(0.6, death_animation.lifetime) if death_animation else 1.0
	await get_tree().create_timer(death_anim_duration).timeout
	if not is_inside_tree():
		return
	GameManager.trigger_game_over()

func revive(Player_lives: int) -> void:
	self.lives = Player_lives
	GameManager.player_lives = Player_lives
	_debug_log("Player revived with " + str(Player_lives) + " lives")

	set_physics_process(true)
	set_process(true)

	# Restore player stats
	GameManager.player_manager.restore_player_stats(self)

	# Set spawn position
	if GameManager.player_manager.player_spawn_position == Vector2.ZERO:
		GameManager.player_manager.set_spawn_position()

	_animate_revival()
	_setup_revival_state_before_invincibility()
	revive_service.play_revive_animation_then_start_invincibility(REVIVE_INVINCIBILITY_DURATION)

func _animate_revival() -> void:
	var target_pos = GameManager.player_manager.player_spawn_position - Vector2(0, 500)
	var start_pos = target_pos + Vector2(0, 3500)
	global_position = start_pos

	if is_inside_tree():
		var tween := create_tween()
		if tween:
			tween.tween_property(self, "global_position", target_pos, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _setup_revival_state_before_invincibility() -> void:
	if death_animation:
		death_animation.emitting = false

	revive_service.prepare_revival_state()
	death_in_progress = false
	is_alive = true
	GameManager.request_game_over_clear("Player._setup_revival_state")
	_debug_log("Revival state setup complete; waiting for Player_revive animation")

func set_lives(new_lives: int) -> void:
	lives = clamp(new_lives, 0, max_life)
	GameManager.player_lives = lives
	_debug_log("Player lives set to: " + str(lives))

func set_stats(attack_level_value: int, bullet_damage_value: int, base_bullet_damage_value: int, shadow_mode_active: bool, super_mode_active: bool = false) -> void:
	_reset_firing_positions()
	_update_game_manager_stats(attack_level_value, bullet_damage_value, base_bullet_damage_value, shadow_mode_active, super_mode_active)
	_setup_firing_positions()
	_apply_mode_effects(shadow_mode_active, super_mode_active)

func _reset_firing_positions() -> void:
	for child in firing_positions.get_children():
		if child.name not in ["LeftGun", "RightGun"]:
			child.queue_free()
	mode_service.clear_super_mode_spawn_cache()

func _update_game_manager_stats(attack_level_value: int, bullet_damage_value: int, base_bullet_damage_value: int, shadow_mode_active: bool, super_mode_active: bool = false) -> void:
	GameManager.player_manager.player_stats["attack_level"] = clamp(attack_level_value, 0, GameManager.player_manager.max_attack_level)
	GameManager.player_manager.player_stats["bullet_damage"] = bullet_damage_value
	GameManager.player_manager.player_stats["base_bullet_damage"] = base_bullet_damage_value
	GameManager.player_manager.player_stats["is_shadow_mode_active"] = shadow_mode_active
	GameManager.player_manager.player_stats["is_super_mode_active"] = super_mode_active

func _setup_firing_positions() -> void:
	for i in range(1, GameManager.player_manager.player_stats["attack_level"] + 1):
		add_firing_position(i)

func _apply_mode_effects(shadow_mode_active: bool, super_mode_active: bool = false) -> void:
	mode_service.apply_mode_effects(shadow_mode_active, super_mode_active)

func increase_bullet_damage(amount: int) -> void:
	if GameManager.player_manager.player_stats.get("attack_level", 0) >= GameManager.player_manager.max_attack_level:
		GameManager.score += 100
		_show_overclocked_notification()
		TutorialManager.notify_overclock_reached()
		return
	apply_bullet_damage_increase(amount)

func _show_overclocked_notification() -> void:
	if power_up_notification:
		power_up_notification.text = "OVERCLOCKED"
		power_up_notification.visible = true
		get_tree().create_timer(2.0).timeout.connect(func(): power_up_notification.visible = false)

func apply_bullet_damage_increase(amount: int) -> void:
	var attack_level: int = int(GameManager.player_manager.player_stats.get("attack_level", 0))
	var balanced_gain: int = mode_service.get_balanced_upgrade_gain(amount, attack_level, GameManager.player_manager.max_attack_level)
	var next_base_damage := mode_service.get_balanced_bullet_damage(
		int(GameManager.player_manager.player_stats.get("base_bullet_damage", GameManager.player_manager.default_bullet_damage)) + balanced_gain
	)
	GameManager.player_manager.player_stats["base_bullet_damage"] = next_base_damage
	GameManager.player_manager.player_stats["bullet_damage"] = next_base_damage
	GameManager.player_manager.player_stats["attack_level"] += 1
	add_firing_position(GameManager.player_manager.player_stats["attack_level"])

	if GameManager.player_manager.player_stats.get("is_shadow_mode_active", false) and not GameManager.player_manager.player_stats.get("is_super_mode_active", false):
		var shadow_multiplier: float = float(GameManager.get_game_settings_section("player_balance").get("shadow_damage_multiplier", 1.75))
		GameManager.player_manager.player_stats["bullet_damage"] = mode_service.get_balanced_bullet_damage(
			int(GameManager.player_manager.player_stats["base_bullet_damage"] * shadow_multiplier)
		)

	# Notify GameManager that ship stats have been updated
	GameManager.notify_ship_stats_updated(ship_id, GameManager.player_manager.player_stats["base_bullet_damage"])

func add_firing_position(level: int) -> void:
	var new_marker := Marker2D.new()
	new_marker.name = "FiringPosition%d" % level
	var angle := deg_to_rad(spread_angle_increment * level)
	var offset := Vector2(spawn_point_offset, 0).rotated(angle)
	new_marker.position = offset
	new_marker.rotation = angle
	firing_positions.add_child(new_marker)

	var mirror_marker := Marker2D.new()
	mirror_marker.name = "FiringPosition%d_Mirror" % level
	mirror_marker.position = Vector2(-offset.x, offset.y)
	mirror_marker.rotation = -angle
	firing_positions.add_child(mirror_marker)

func activate_super_mode(multiplier_div: float, duration: float) -> void:
	mode_service.set_super_mode_active(true)
	apply_super_mode_effects(multiplier_div, duration)

func apply_super_mode_effects(multiplier_div: float, duration: float) -> void:
	mode_service.apply_super_mode_effects(multiplier_div, duration)

func add_super_mode_spawn_points() -> void:
	mode_service.add_super_mode_spawn_points()

func _on_super_mode_timeout() -> void:
	mode_service.on_super_mode_timeout()

func _on_player_life_changed(new_lives: int) -> void:
	lives = clamp(new_lives, 0, max_life)
	_debug_log("Player lives updated via signal: " + str(lives))

	if lives <= 0:
		_handle_death()

func increase_life(amount: int) -> void:
	if amount <= 0:
		return

	lives = min(3, lives + amount)  # Cap lives at 3
	GameManager.player_lives = lives
	_debug_log("Player lives increased to: " + str(lives))

	GameManager.save_progress_if_enabled()

func _on_game_over_triggered() -> void:
	is_alive = false
	death_in_progress = false
	_remove_all_satellites()
	queue_free()

func _on_victory_pose():
	_debug_log("Playing victory pose animation")
	if animation_player:
		animation_player.play("Player_sweep")
	else:
		_debug_log("AnimationPlayer not found, cannot play victory pose")

func _on_level_completed(_level_num):
	input_enabled = false
	GameManager.request_shadow_mode_deactivate_silent("Player._on_level_completed")
	var base_damage: int = int(
		GameManager.player_manager.player_stats.get(
			"base_bullet_damage",
			GameManager.player_manager.default_bullet_damage
		)
	)
	set_stats(0, base_damage, base_damage, false, false)
	GameManager.save_progress_if_enabled()

	# Rebuild satellites so they drop temporary runtime state before the next level.
	update_satellites_from_selection()

func _on_ship_stats_updated(updated_ship_id: String, new_damage: int) -> void:
	"""Handle ship stat updates from upgrade system"""
	if updated_ship_id == ship_id:
		# Update this player's base damage if it matches the updated ship
		base_bullet_damage = new_damage
		# Update PlayerManager's player stats
		GameManager.player_manager.player_stats["base_bullet_damage"] = new_damage
		# If not in shadow mode or super mode, also update current bullet damage
		if not GameManager.player_manager.player_stats.get("is_shadow_mode_active", false) and not GameManager.player_manager.player_stats.get("is_super_mode_active", false):
			GameManager.player_manager.player_stats["bullet_damage"] = new_damage
		mode_service.update_ship_context(ship_id, original_texture, original_speed)
		satellite_service.refresh_satellite_layout()
		_debug_log("Ship stats updated: damage is now %d for ship %s" % [new_damage, ship_id])

func _on_player_manager_satellites_changed() -> void:
	"""Handle when PlayerManager's selected satellites are changed"""
	satellite_service.update_satellites_from_selection()
	_debug_log("Satellite selection updated from PlayerManager")
func _calculate_satellite_offset(position_index: int) -> Vector2:
	return satellite_service.calculate_satellite_offset(position_index)

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Player_sweep":
		_debug_log("Victory pose animation finished")
		emit_signal("victory_pose_done", anim_name)
	else:
		revive_service.on_animation_finished(anim_name, REVIVE_INVINCIBILITY_DURATION)

# Handle collisions with enemies and enemy bullets
func _on_area_entered(area: Area2D) -> void:
	if not combat_service.can_process_collision(is_alive, revive_service):
		return

	# Handle enemy collision (direct contact damage)
	if area.is_in_group("Enemy") or area.is_in_group("Enemies"):
		_handle_enemy_collision(area)

	if area is Powerup:
		area.applyPowerup(self)

	# Handle enemy bullet collision
	elif area.is_in_group("EnemyBullet"):
		_handle_enemy_bullet_collision(area)

	# Handle boss collision
	elif area.is_in_group("Boss"):
		_handle_enemy_collision(area)

func _handle_enemy_collision(enemy: Area2D) -> void:
	"""Handle direct collision with enemy ships"""
	if not combat_service.can_process_collision(is_alive, revive_service):
		return

	# Deal damage to player
	combat_service.apply_enemy_contact(enemy, Callable(self, "damage"))
	_debug_log("Player collided with enemy: %s" % enemy.name)

func _handle_enemy_bullet_collision(bullet: Area2D) -> void:
	"""Handle collision with enemy bullets"""
	if not combat_service.can_process_collision(is_alive, revive_service):
		return

	# Deal damage to player
	var bullet_damage: int = combat_service.apply_bullet_hit(bullet, Callable(self, "damage"))
	_debug_log("Player hit by bullet: %s (damage: %d)" % [bullet.name, bullet_damage])

func is_just_revived() -> bool:
	return revive_service.just_revived
