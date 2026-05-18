extends Node3D

signal plate_activated(is_active: bool)

@export var sink_distance: float = 0.15
@export var transition_speed: float = 0.2 # Fixed typo here

@onready var plate_mesh = $plate_area/MeshInstance3D 

var original_y: float

func _ready():
	original_y = plate_mesh.position.y
	$plate_area.body_entered.connect(_on_entered)
	$plate_area.body_exited.connect(_on_exited)
	
func _on_entered(body):
	# Check the body itself, OR check the ultimate owner of the body
	var is_player = body.is_in_group("player") or (body.owner and body.owner.is_in_group("player"))
	
	if is_player:
		print("PLAYER DETECTED - Sinking Plate")
		animate_plate(original_y - sink_distance)
		plate_activated.emit(true)
	else:
		# This will tell us exactly what weird sub-node is touching the plate
		var owner_name = body.owner.name if body.owner else "No Owner"
		print("Ignored Collision -> Node: ", body.name, " | Owner: ", owner_name)

func _on_exited(body):
	var is_player = body.is_in_group("player") or (body.owner and body.owner.is_in_group("player"))
	
	if is_player:
		print("PLAYER LEFT - Raising Plate")
		animate_plate(original_y)
		plate_activated.emit(false)
# THE CUSTOM FUNCTION
func animate_plate(target_y: float):
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(plate_mesh, "position:y", target_y, transition_speed)
