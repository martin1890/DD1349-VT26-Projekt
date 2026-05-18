extends Node3D

@onready var arrows_container = $Arrows

func _on_pressure_plate_activated(is_active: bool):
	if is_active:
		print("🏹 TRAP SPRUNG! Triggering fire_volley()...")
		fire_volley()

func fire_volley():
	var child_count = arrows_container.get_child_count()
	print("Dispenser checking container. Found ", child_count, " total child nodes.")
	
	for arrow in arrows_container.get_children():
		var has_script = arrow.has_method("launch")
		print("-> Node Name: ", arrow.name, " | Attached to Arrow.gd script?: ", has_script)
		
		if has_script:
			arrow.launch()
