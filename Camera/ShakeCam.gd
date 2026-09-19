extends Camera2D

@export var shakeBaseAmount := 1.0
@export var shakeDampening := 0.075

var shakeAmount := 0.0

func _ready() -> void:
	# Idle until the first shake: avoids writing the camera transform every
	# frame when nothing is shaking.
	set_process(false)

func _process(_delta):
	if shakeAmount > 0:
		position.x = randf_range(-shakeBaseAmount, shakeBaseAmount) * shakeAmount
		position.y = randf_range(-shakeBaseAmount, shakeBaseAmount) * shakeAmount
		shakeAmount = lerp(shakeAmount, 0.0, shakeDampening)
		if shakeAmount < 0.01:
			# Shake finished: snap back and stop processing until the next one.
			shakeAmount = 0.0
			position = Vector2.ZERO
			set_process(false)
	elif position != Vector2.ZERO:
		position = Vector2(0, 0)

func shake(magnitude: float):
	if not is_processing():
		set_process(true)
	shakeAmount += magnitude
