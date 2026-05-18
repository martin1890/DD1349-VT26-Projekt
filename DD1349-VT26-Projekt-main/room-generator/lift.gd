extends AnimatableBody3D

@export var travel_distance: float = 10.0
@export var move_speed: float = 3.0

@onready var start_pos = position.y
@onready var end_pos = position.y + travel_distance

enum Status { AT_BOTTOM, MOVING, AT_TOP }
var current_status = Status.AT_BOTTOM

# THE SAFETY LATCH
var waiting_for_exit: bool = false

@onready var plate = $pressure_plate 

func _on_pressure_plate_activated(is_active: bool):
	if current_status == Status.MOVING:
		return
		
	# 1. If the player steps OFF the plate, unlock the safety latch
	if not is_active:
		waiting_for_exit = false
		print("Player stepped off. Plate reset and ready.")
		return

	# 2. If the safety latch is active, ignore the player standing here
	if waiting_for_exit:
		return
		
	# 3. Otherwise, proceed with moving the lift
	if is_active:
		if plate:
			var plate_area = plate.get_node("plate_area")
			plate_area.set_deferred("monitoring", false)
		
		var target_y = end_pos if current_status == Status.AT_BOTTOM else start_pos
		current_status = Status.MOVING
		
		var duration = abs(position.y - target_y) / move_speed
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(self, "position:y", target_y, duration)
		
		tween.finished.connect(_on_lift_arrived.bind(target_y))

func _on_lift_arrived(arrived_y: float):
	if is_equal_approx(arrived_y, end_pos):
		current_status = Status.AT_TOP
		print("Lift arrived at the TOP")
	else:
		current_status = Status.AT_BOTTOM
		print("Lift arrived at the BOTTOM")
		
	# Lock the lift! It will refuse to move until waiting_for_exit becomes false
	waiting_for_exit = true
		
	if plate:
		var plate_area = plate.get_node("plate_area")
		plate_area.set_deferred("monitoring", true)
		
		if plate.has_method("animate_plate"):
			plate.animate_plate(plate.original_y)
