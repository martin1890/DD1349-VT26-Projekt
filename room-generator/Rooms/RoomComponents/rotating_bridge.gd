extends StaticBody3D

@export var button: Node3D
@export var target_angle_deg: float = 90.0
@export var rotation_speed: float = 5.0
@export var stop_threshold_deg: float = 0.5

var should_change: bool = false

func _ready():
	var button = get_node("../../Button")
	button.pressed.connect(_change_direction)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("rotate_bridge"):
		should_change = true

	if should_change:
		change_position(delta)

func _change_direction():
	target_angle_deg += 43

func change_position(delta: float) -> void:
	var target_y := deg_to_rad(target_angle_deg)
	rotation.y = lerp_angle(rotation.y, target_y, rotation_speed * delta)

	if abs(angle_difference(rotation.y, target_y)) < deg_to_rad(stop_threshold_deg):
		rotation.y = target_y
		should_change = false
		
		
