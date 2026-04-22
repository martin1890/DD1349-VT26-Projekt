extends Node3D

@export var swing_axis := Vector3(1, 0, 0)
@export var max_angle_degrees := 35.0
@export var swing_speed := 1.5
@export var phase := 0.0

var _base_rotation: Vector3

func _ready() -> void:
	_base_rotation = rotation

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var angle := deg_to_rad(max_angle_degrees) * sin(t * swing_speed + phase)

	rotation = _base_rotation

	if swing_axis.x != 0:
		rotation.x = _base_rotation.x + angle
	elif swing_axis.y != 0:
		rotation.y = _base_rotation.y + angle
	else:
		rotation.z = _base_rotation.z + angle
