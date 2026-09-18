extends Area2D
class_name HellPatternBullet

# Speed of the bullet in pixels per second.
@export var speed: float = 1200.0

# Damage dealt to the player.
@export var damage: int = 1

# Direction of movement.
var direction: Vector2 = Vector2.ZERO

# Velocity vector of the bullet.
var velocity: Vector2 = Vector2.ZERO

# Lifetime of the bullet in seconds.
@export var lifetime: float = 6.0

# Internal timer for tracking lifetime.
var _lifetime_timer: float = 0.0

# Rotation speed for visual effect
var rotation_speed: float = 10.0

# Scale variation for visual effect
var scale_variation: float = 0.0

func _ready() -> void:
	if speed <= 0:
		push_warning(" HellPatternBullet speed is non-positive. Setting to 1200.0.")
		speed = 1200.0
	if damage <= 0:
		push_warning(" HellPatternBullet damage is non-positive. Setting to 1.")
		damage = 1
	if lifetime <= 0:
		push_warning(" HellPatternBullet lifetime is non-positive. Setting to 7.0.")
		lifetime = 7.0
	
	# Add some visual variation
	scale_variation = randf_range(0.8, 1.2)
	scale = Vector2(scale_variation, scale_variation)
	rotation_speed = randf_range(3.0, 7.0)

	var area_callable := Callable(self, "_on_area_entered")
	if not area_entered.is_connected(area_callable):
		area_entered.connect(area_callable)

func _physics_process(delta: float) -> void:
	# Move the bullet
	if direction != Vector2.ZERO:
		velocity = direction * speed
	global_position += velocity * delta
	
	# Rotate for visual effect
	rotation += rotation_speed * delta
	
	# Pulsing effect
	var pulse = sin(_lifetime_timer * 10.0) * 0.1 + 1.0
	scale = Vector2(scale_variation * pulse, scale_variation * pulse)
	
	# Handle lifetime
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		queue_free()

# Sets the direction of the bullet.
func set_direction(dir: Vector2) -> void:
	direction = dir.normalized()

# Sets the speed of the bullet.
func set_speed(new_speed: float) -> void:
	if new_speed <= 0:
		push_warning(" HellPatternBullet speed cannot be non-positive. Setting to 1200.0.")
		speed = 1200.0
	else:
		speed = new_speed

# Sets the lifetime of the bullet.
func set_lifetime(time: float) -> void:
	if time <= 0:
		push_warning(" HellPatternBullet lifetime cannot be non-positive. Setting to 7.0.")
		lifetime = 7.0
	else:
		lifetime = time
		_lifetime_timer = 0.0

# Returns the damage value of the bullet.
func get_damage() -> int:
	return damage

# Sets the damage value of the bullet.
func set_damage(new_damage: int) -> void:
	if new_damage <= 0:
		push_warning(" HellPatternBullet damage is non-positive. Setting to 1.")
		damage = 1
	else:
		damage = new_damage

# Handles collision with the player.
func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("Player"):
		# Check if player is in grace period after revival
		if area.has_method("is_just_revived") and area.is_just_revived():
			return
		area.call("damage", damage)
		queue_free()

# Frees the bullet when it exits the screen.
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
