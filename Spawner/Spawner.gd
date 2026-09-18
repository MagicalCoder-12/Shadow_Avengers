extends Node2D

@export var spawn_padding: float = 20.0
@export var minPowerupSpawnTime: float = 5.0
@export var maxPowerupSpawnTime: float = 20.0

var powerup_scenes := [
	preload("res://Powerups/Attack_boost_powerup.tscn"),
	preload("res://Powerups/SuperMode.tscn"),
	preload("res://Meteor/Astroid.tscn"),
	preload("res://Powerups/Health.tscn")
]
var view_rect: Rect2

@onready var powerupSpawnTimer := $PowerupSpawnTimer
var level: Node

func _ready():
	level = get_tree().current_scene if get_tree() else null
	randomize()
	view_rect = get_viewport_rect()
	# Connect to GameManager signals to stop spawning on game over or level completion
	GameManager.game_over_triggered.connect(_on_game_over_triggered)
	GameManager.level_completed.connect(_on_level_completed)
	# Start timer only if game is not over or level not completed
	if level and level.get("game_over") != true and level.get("level_completed_shown") != true:
		powerupSpawnTimer.start(randf_range(minPowerupSpawnTime, maxPowerupSpawnTime))
	else:
		powerupSpawnTimer.stop()

func get_random_spawn_pos(node: Node) -> Vector2:
	var size: Vector2 = Vector2.ZERO
	
	# Check for CollisionShape2D (used by powerups)
	var collision_shape = node.get_node_or_null("CollisionShape2D")
	if collision_shape and collision_shape.shape:
		var shape = collision_shape.shape
		if shape is RectangleShape2D:
			size = shape.extents * 2  # extents is half the size, so multiply by 2
		elif shape is CircleShape2D:
			size = Vector2(shape.radius * 2, shape.radius * 2)  # Diameter for width and height
		else:
			# Fallback for other shapes
			size = Vector2(50, 50)  # Default size if shape type is unknown
	
	# Check for CollisionPolygon2D (used by asteroid)
	var collision_polygon = node.get_node_or_null("CollisionPolygon2D")
	if collision_polygon:
		var polygon = collision_polygon.polygon
		if polygon.size() > 0:
			var min_pos = polygon[0]
			var max_pos = polygon[0]
			for point in polygon:
				min_pos.x = min(min_pos.x, point.x)
				min_pos.y = min(min_pos.y, point.y)
				max_pos.x = max(max_pos.x, point.x)
				max_pos.y = max(max_pos.y, point.y)
			size = max_pos - min_pos
	
	# If no collision shape found, use a default size
	if size == Vector2.ZERO:
		size = Vector2(50, 50)  # Default size as fallback
	
	var min_x := size.x / 2 + spawn_padding
	var max_x := view_rect.size.x - size.x / 2 - spawn_padding
	var min_y := size.y / 2 + spawn_padding
	return Vector2(randf_range(min_x, max_x), min_y)

func _on_PowerupSpawnTimer_timeout() -> void:
	# Stop spawning if game is over or level is completed
	if level and (level.get("game_over") == true or level.get("level_completed_shown") == true):
		powerupSpawnTimer.stop()
		return
	
	# Weighted random selection:
	# - Asteroid: 50%
	# - Attack Boost: 25%
	# - Super Mode: 15%
	# - Health: 10%
	var roll = randf() * 100  # Random number between 0 and 100
	var selected_scene
	var is_astroid = false
	
	if roll < 50:
		selected_scene = powerup_scenes[2]  # Asteroid
		is_astroid = true
	elif roll < 75:
		selected_scene = powerup_scenes[0]  # Attack Boost
	elif roll < 90:
		selected_scene = powerup_scenes[1]  # Super Mode
	else:
		selected_scene = powerup_scenes[3]  # Health
	
	if is_astroid:
		var num_asteroids = randi_range(1, 2)
		for i in range(num_asteroids):
			var astroid: Node = selected_scene.instantiate()
			astroid.position = get_random_spawn_pos(astroid)
			SceneSpawnService.spawn_child(astroid)
	else:
		# Spawn a single powerup
		var powerup: Node = selected_scene.instantiate()
		powerup.position = get_random_spawn_pos(powerup)
		SceneSpawnService.spawn_child(powerup)
	
	# Restart the timer
	powerupSpawnTimer.start(randf_range(minPowerupSpawnTime, maxPowerupSpawnTime))

func _on_game_over_triggered():
	# Stop the timer when game over is triggered
	powerupSpawnTimer.stop()

func _on_level_completed(_level_num: int):
	# Stop the timer when level is completed
	powerupSpawnTimer.stop()
