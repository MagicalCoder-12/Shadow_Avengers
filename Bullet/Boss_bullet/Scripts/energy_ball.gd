extends Area2D
class_name EnergyBall

## Speed of the energy ball in pixels per second.
@export var speed: float = 1000.0

## Damage dealt to the player.
@export var damage: int = 1

## Direction of movement.
@export var direction: Vector2 = Vector2.DOWN

## Minimum lifetime of the energy ball in seconds.
@export var min_lifetime: float = 2.5

## Maximum lifetime of the energy ball in seconds.
@export var max_lifetime: float = 4.0

## Radius of the explosion damage area.
@export var explosion_radius: float = 60.0

## Enable/Disable visual explosion.
@export var show_explosion_vfx: bool = true

## Color of the explosion shape.
@export var explosion_color: Color = Color(1, 0.8, 0.2)

## Internal timer for tracking lifetime.
var _lifetime_timer: float = 0.0

## Lifetime selected for this spawned instance.
var lifetime: float = 2.5

## Flag to prevent multiple explosions
var _is_exploding: bool = false

## Cache the collision shape
var _collision_shape: CollisionShape2D


func _ready() -> void:
	_collision_shape = $CollisionShape2D if has_node("CollisionShape2D") else null
	
	if direction.length() > 0:
		direction = direction.normalized()

	if min_lifetime <= 0.0:
		min_lifetime = 2.5
	if max_lifetime < min_lifetime:
		max_lifetime = min_lifetime
	lifetime = randf_range(min_lifetime, max_lifetime)
	
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _is_exploding:
		return

	# Move the energy ball
	position += direction * speed * delta

	# Track lifetime
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		explode()


func _on_area_entered(area: Area2D) -> void:
	if _is_exploding:
		return
		
	if area.is_in_group("Player"):
		if area.has_method("is_just_revived") and area.is_just_revived():
			return
		
		_apply_damage(area)
		explode()


func explode() -> void:
	if _is_exploding:
		return
	
	_is_exploding = true
	
	# --- PERFORMANCE OPTIMIZATION ---
	# We disable physics here because the ball no longer needs to move.
	# THIS DOES NOT AFFECT DAMAGE because we use Math (distance_to), 
	# not Physics (get_overlapping_areas).
	set_physics_process(false)
	set_process(false)
	
	# Disable collision shape so it doesn't interfere with other physics objects
	if _collision_shape:
		_collision_shape.disabled = true
	
	# Remove from physics layers entirely
	collision_layer = 0
	collision_mask = 0
	
	# --- DAMAGE CHECK ---
	# This runs immediately. It uses math, so it works even though physics is disabled.
	_deal_explosion_damage()
	
	# --- VISUALS ---
	var visual_duration: float = 0.0
	if show_explosion_vfx:
		visual_duration = _create_explosion_shape()
	
	# --- CLEANUP ---
	# Wait for visuals to finish, then free. 
	# The node stays in the tree during 'await', so global_position remains valid.
	if visual_duration > 0.0:
		await get_tree().create_timer(visual_duration).timeout
	
	if is_inside_tree():
		queue_free()


func _deal_explosion_damage() -> void:
	var players = get_tree().get_nodes_in_group("Player")
	
	for player in players:
		if not is_instance_valid(player) or not player is Node2D:
			continue
			
		# MATH-BASED CHECK: 
	 # This does not require the Physics Server or active CollisionShapes.
		# It works even if physics is disabled on this node.
		if global_position.distance_to(player.global_position) <= explosion_radius:
			if player.has_method("is_just_revived") and player.is_just_revived():
				continue
			
			_apply_damage(player)


func _create_explosion_shape() -> float:
	var visual_duration: float = 0.4
	
	var visual_node = ExplosionVisual.new()
	visual_node.color = explosion_color
	visual_node.radius = explosion_radius
	visual_node.position = Vector2.ZERO
	
	add_child(visual_node)
	
	var tween = create_tween()
	tween.tween_property(visual_node, "scale", Vector2.ONE * 1.5, visual_duration).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(visual_node, "modulate:a", 0.0, visual_duration).set_ease(Tween.EASE_OUT)
	
	tween.tween_callback(visual_node.queue_free)
	
	return visual_duration


func _apply_damage(area: Area2D) -> void:
	if area.has_method("damage"):
		area.call("damage", damage)


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	if not _is_exploding:
		queue_free()


class ExplosionVisual extends Node2D:
	var color: Color = Color.WHITE
	var radius: float = 50.0
	
	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color, 2.0, true)
