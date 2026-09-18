extends Area2D
class_name HomingBullet

## Speed of the bullet in pixels per second.
@export var speed: float = 3000.0

## Damage dealt to the player.
@export var damage: int = 1

## Rate at which the bullet turns towards the target (0.0 to 1.0).
@export var turn_rate: float = 0.05

## Whether the bullet is active (can move and deal damage).
@export var is_active: bool = true

## Lifetime of the bullet in seconds (0.0 means no lifetime limit).
@export var lifetime: float = 0.0

## Target position for homing (defaults to player position).
var target: Vector2

## Velocity vector of the bullet.
var velocity: Vector2

## Internal timer for tracking lifetime.
var _lifetime_timer: float = 0.0

func _ready() -> void:
	if speed <= 0:
		push_warning(" HomingBullet speed is non-positive. Setting to 300.0.")
		speed = 300.0
	if damage <= 0:
		push_warning(" HomingBullet damage is non-positive. Setting to 1.")
		damage = 1
	if turn_rate < 0.0 or turn_rate > 1.0:
		push_warning(" HomingBullet turn_rate out of range. Setting to 0.05.")
		turn_rate = 0.05
	
	# Find the player for homing
	var player: Node = get_tree().get_first_node_in_group("Player")
	target = player.global_position if player else global_position + Vector2(0, 1000)
	
	# Initialize velocity
	velocity = Vector2.UP.rotated(global_rotation) * speed
	
func _physics_process(delta: float) -> void:
	if is_active:
		# Update target position
		var player: Node = get_tree().get_first_node_in_group("Player")
		if player:
			target = player.global_position
		
		# Adjust velocity towards target
		var direction: Vector2 = (target - global_position).normalized()
		velocity = velocity.lerp(direction * speed, turn_rate)
		global_position += velocity * delta
		global_rotation = velocity.angle()
		
		# Handle lifetime
		if lifetime > 0.0:
			_lifetime_timer += delta
			if _lifetime_timer >= lifetime:
				call_deferred("queue_free")

## Sets the target position for homing.
func set_target(pos: Vector2) -> void:
	target = pos

## Sets the lifetime of the bullet in seconds.
func set_lifetime(time: float) -> void:
	if time < 0.0:
		push_warning(" HomingBullet lifetime cannot be negative. Setting to 0.0.")
		lifetime = 0.0
	else:
		lifetime = time
		_lifetime_timer = 0.0  # Reset timer when setting new lifetime

## Returns the damage value of the bullet.
func get_damage() -> int:
	return damage

## Sets the damage value of the bullet.
func set_damage(new_damage: int) -> void:
	if new_damage <= 0:
		push_warning(" HomingBullet damage is non-positive. Setting to 1.")
		damage = 1
	else:
		damage = new_damage

## Handles collision with the player.
func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("Player"):
		# Check if player is in grace period after revival
		if area.has_method("is_just_revived") and area.is_just_revived():
			return
		area.call("damage", damage)
		call_deferred("queue_free")

## Frees the bullet when it exits the screen.
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	call_deferred("queue_free")
