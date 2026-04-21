extends Camera3D

@export var mouse_sensitivity: float = 0.002

var pitch: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Rotate the player horizontally
		get_parent().rotate_y(-event.relative.x * mouse_sensitivity)

		# Rotate the camera vertically
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-80), deg_to_rad(80))
		rotation.x = pitch
