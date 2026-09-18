extends Area2D

@export var pull_force: float = 500.0
@export var lifetime: float = 3.0
@export var beam_width: float = 50.0
@export var beam_length: float = 800.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D  # Assuming child AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D  # Assuming a child CollisionShape2D for the beam area

var is_active: bool = true

func _ready() -> void:
	if animated_sprite:
		animated_sprite.play("default")
	else:
		push_warning(" No AnimatedSprite2D found in TractorBeam.")
	
	# Set up collision shape for the beam (vertical downward)
	if collision_shape:
		var shape = RectangleShape2D.new()
		shape.extents = Vector2(beam_width / 2, beam_length / 2)
		collision_shape.shape = shape
		collision_shape.position = Vector2(0, beam_length / 2)  # Position downward
	else:
		push_warning(" No CollisionShape2D found in TractorBeam.")
	
	# Start lifetime timer
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_timeout)

func _physics_process(delta: float) -> void:
	if is_active:
		for area in get_overlapping_areas():
			if area.is_in_group("Player"):
				# Pull player towards the beam's origin (boss position)
				var direction = (global_position - area.global_position).normalized()
				area.velocity += direction * pull_force * delta
				# Optional: Reduce player control while pulled
				if area.has_method("apply_tractor_effect"):
					area.apply_tractor_effect(delta)

func _on_lifetime_timeout() -> void:
	is_active = false
	if animated_sprite:
		var tween = create_tween()
		tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.5)
		await tween.finished
	queue_free()
