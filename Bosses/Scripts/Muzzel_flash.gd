extends Node2D

signal effect_finished

@onready var particles: CPUParticles2D = $CPUParticles2D

var _finished: bool = false

func _ready() -> void:
	if particles and not particles.finished.is_connected(_on_particles_finished):
		particles.finished.connect(_on_particles_finished, CONNECT_ONE_SHOT)
	if particles:
		particles.emitting = false
		particles.restart()
		particles.emitting = true
	_schedule_fallback_cleanup()

func _schedule_fallback_cleanup() -> void:
	var fallback_duration := 0.3
	if particles:
		fallback_duration = max(fallback_duration, particles.lifetime + 0.05)
	await get_tree().create_timer(fallback_duration).timeout
	if is_inside_tree():
		_finish_effect()

func _on_particles_finished() -> void:
	_finish_effect()

func _finish_effect() -> void:
	if _finished:
		return
	_finished = true
	effect_finished.emit()
	queue_free()
