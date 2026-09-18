extends Area2D

@export var damage: int = 2
@export var fallback_lifetime: float = 1.2

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var audio_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D

var _is_cleaning_up: bool = false
var _damaged_targets: Dictionary = {}

func _ready() -> void:
	monitoring = true
	monitorable = true
	var area_entered_callable := Callable(self, "_on_area_entered")
	if not area_entered.is_connected(area_entered_callable):
		area_entered.connect(area_entered_callable)

	if animated_sprite_2d:
		animated_sprite_2d.frame = 0
		animated_sprite_2d.play("default")
		var animation_finished_callable := Callable(self, "_on_animated_sprite_2d_animation_finished")
		if not animated_sprite_2d.animation_finished.is_connected(animation_finished_callable):
			animated_sprite_2d.animation_finished.connect(animation_finished_callable)

	var played_audio_via_manager: bool = false
	if audio_player_2d and audio_player_2d.stream and AudioManager:
		AudioManager.play_sound_effect(audio_player_2d.stream, "Explosion")
		played_audio_via_manager = true

	# Fallback when AudioManager is unavailable.
	if audio_player_2d and not played_audio_via_manager:
		audio_player_2d.play()

	call_deferred("_apply_initial_overlap_damage")
	_start_fallback_cleanup()

func _apply_initial_overlap_damage() -> void:
	if not is_inside_tree():
		return
	for area in get_overlapping_areas():
		_try_apply_damage(area)

func _on_area_entered(area: Area2D) -> void:
	_try_apply_damage(area)

func _try_apply_damage(area: Area2D) -> void:
	if _is_cleaning_up:
		return
	if not (area is Player):
		return

	var target_id: int = area.get_instance_id()
	if _damaged_targets.has(target_id):
		return
	_damaged_targets[target_id] = true

	if area.has_method("damage"):
		area.damage(damage)

func get_damage() -> int:
	return damage

func _start_fallback_cleanup() -> void:
	if not get_tree():
		return
	await get_tree().create_timer(maxf(0.2, fallback_lifetime)).timeout
	_cleanup()

func _on_animated_sprite_2d_animation_finished() -> void:
	_cleanup()

func _on_explosion_finished() -> void:
	# Backward compatibility for older scene signal bindings.
	_cleanup()

func _cleanup() -> void:
	if _is_cleaning_up:
		return
	_is_cleaning_up = true
	if is_inside_tree():
		queue_free()
