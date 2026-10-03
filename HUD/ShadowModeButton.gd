extends Control
class_name ShadowModeButton

# Signals
signal shadow_mode_requested

# Node references
@onready var texture_button: TextureButton = $TextureButton
@onready var texture_progress_bar: TextureProgressBar = $TextureButton/TextureProgressBar
@onready var label: Label = $TextureButton/Label

# Configuration
@export var max_charge: float = 100.0
@export var charge_per_enemy: float = 6.0

# State
var current_charge: float = 0.0
var is_ready: bool = false
var is_enabled: bool = false

func _ready() -> void:
	update_display()

func set_enabled(enabled: bool) -> void:
	is_enabled = enabled
	visible = enabled
	if not enabled:
		reset_charge()

func add_charge(amount: float = charge_per_enemy) -> void:
	if not is_enabled:
		return
		
	current_charge = clamp(current_charge + amount, 0.0, max_charge)
	update_display()
	
	# Check if ready
	if current_charge >= max_charge and not is_ready:
		is_ready = true
		update_display()
		TutorialManager.notify_shadow_ready()

func reset_charge() -> void:
	current_charge = 0.0
	is_ready = false
	update_display()

func set_charge(charge: float) -> void:
	current_charge = clamp(charge, 0.0, max_charge)
	is_ready = current_charge >= max_charge
	update_display()

func get_charge_percentage() -> float:
	return (current_charge / max_charge) * 100.0

func update_display() -> void:
	if not is_node_ready():
		return
		
	# Update progress bar
	if texture_progress_bar:
		texture_progress_bar.value = get_charge_percentage()
		
	# Update label text
	if label:
		if is_ready:
			label.text = "READY!"
		else:
			var percentage = int(get_charge_percentage())
			label.text = "%d%%" % percentage

func show_charge_gain_effect() -> void:
	if not is_inside_tree():
		return

func _on_texture_button_pressed() -> void:
	if is_ready and is_enabled:
		shadow_mode_requested.emit()
		reset_charge()
