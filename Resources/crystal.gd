extends Area2D

# === VARIABLES ===
@export var bounce_time: float = 0.0
@export var bounce_duration: float = 5.0
@export var bounce_amplitude: float = 100.0
@export var bounce_frequency: float = 1.5
var initial_position: Vector2
var velocity: Vector2 = Vector2.ZERO
var coin_gravity: float
var restitution: float
var is_grounded: bool = false
var bottom_bounds: float
var crystal_value: int = 3  # Default value
var is_collected: bool = false
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D


# === READY ===
func _ready() -> void:
	# Add to Crystals group for easier management
	add_to_group("Crystals")
	# Hide Sprite2D, use AnimatedSprite2D for visuals
	animated_sprite_2d.hide()
	
	# Initialize gravity from project settings
	coin_gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
	
	# Calculate restitution based on bounce_frequency (maps to 0.5-0.9 range)
	restitution = clamp(0.5 + bounce_frequency * 0.2, 0.5, 0.9)
	
	# Initialize bottom bounds from viewport
	bottom_bounds = get_viewport().get_visible_rect().size.y
	
	# Store initial position for reference
	initial_position = global_position
	
	# Create and start a timer for lifespan
	var timer = Timer.new()
	timer.name = "LifespanTimer"
	timer.wait_time = bounce_duration
	timer.one_shot = true
	timer.timeout.connect(_on_lifespan_timeout)
	add_child(timer)
	timer.start()
	
	# Connect area_entered signal
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

# Function to set the crystal value
func set_value(value: int) -> void:
	crystal_value = value

# === PHYSICS PROCESS ===
func _physics_process(delta: float) -> void:
	if is_collected:
		return

	# Track time for lifespan
	bounce_time += delta
	
	# Apply gravity
	velocity.y += coin_gravity * delta
	
	# Update position
	global_position += velocity * delta
	
	# Clamp position to bottom bounds to prevent overshooting
	if global_position.y >= bottom_bounds:
		global_position.y = bottom_bounds
		if not is_grounded:
			# Apply initial bounce: fixed velocity scaled by restitution
			velocity.y = -1000.0 * restitution
			is_grounded = true
		elif velocity.y > 0:
			# Apply subsequent bounces
			velocity.y = -abs(velocity.y) * restitution
			if abs(velocity.y) < 0.5:  # Stop bouncing if velocity is too low
				velocity.y = 0

# === SIGNALS ===
func _on_area_entered(area: Area2D) -> void:
	if is_collected or not area.is_in_group("Player"):
		return

	is_collected = true
	GameManager.add_currency("crystals", crystal_value)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if collision_shape_2d:
		collision_shape_2d.set_deferred("disabled", true)
	if has_node("LifespanTimer"):
		var lifespan_timer := get_node("LifespanTimer") as Timer
		if lifespan_timer:
			lifespan_timer.stop()
	if sprite_2d:
		sprite_2d.hide()
	animated_sprite_2d.show()
	animated_sprite_2d.play("collected")
	await get_tree().create_timer(_get_collection_effect_duration()).timeout
	if is_inside_tree():
		queue_free()

func _on_lifespan_timeout() -> void:
	# Queue free the crystal after lifespan expires
	queue_free()

func _get_collection_effect_duration() -> float:
	var duration: float = 0.1
	if animated_sprite_2d and animated_sprite_2d.sprite_frames and animated_sprite_2d.sprite_frames.has_animation("collected"):
		var base_animation_speed: float = float(animated_sprite_2d.sprite_frames.get_animation_speed("collected"))
		var animation_speed: float = base_animation_speed * max(animated_sprite_2d.speed_scale, 0.01)
		if animation_speed > 0.0:
			var frame_count: float = float(animated_sprite_2d.sprite_frames.get_frame_count("collected"))
			duration = max(duration, frame_count / animation_speed)
	return duration + 0.05
