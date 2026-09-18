extends Node2D
class_name PhaseTransitionEffect

## Reference to the AnimationPlayer node.
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	if not animation_player:
		push_error(" AnimationPlayer node not found.")
		queue_free()
		return
	
	# Play the transition animation
	animation_player.play("transition")
	
	# Connect to animation finished to clean up
	animation_player.animation_finished.connect(_on_animation_finished)

## Cleans up the effect after the animation completes.
func _on_animation_finished(_anim_name: String) -> void:
	call_deferred("queue_free")
