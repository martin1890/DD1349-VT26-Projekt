extends StaticBody3D # Changed from Area3D
class_name Lever

@export var target_object: Node3D
@export var flip_duration: float = 0.3

@onready var handle_pivot: Node3D = $HandlePivot

var is_flipped: bool = false
var is_animating: bool = false

# Your Player's RayCast script will look for and call this exact function
func interact() -> void:
	if is_animating:
		return
		
	toggle_lever()

func toggle_lever() -> void:
	print("--- Lever Toggle Triggered ---")
	is_flipped = !is_flipped
	is_animating = true
	
	# Determine target angles
	var lever_target_rot = -90.0 if is_flipped else 0.0
	var object_target_rot = 90.0 if is_flipped else 0.0
	
	print("Current pivot rotation before tween: ", handle_pivot.rotation_degrees)
	
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Force test on the X axis using a Vector3 instead of a string property
	var target_vector = Vector3(lever_target_rot, handle_pivot.rotation_degrees.y, handle_pivot.rotation_degrees.z)
	tween.tween_property(handle_pivot, "rotation_degrees", target_vector, flip_duration)
	
	if target_object:
		tween.tween_property(target_object, "rotation_degrees:x", object_target_rot, flip_duration)
		
	await tween.finished
	print("Pivot rotation after tween finishes: ", handle_pivot.rotation_degrees)
	is_animating = false
