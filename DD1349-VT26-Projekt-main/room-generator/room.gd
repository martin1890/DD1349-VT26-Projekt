extends Node3D

func _ready():
	# SYSTEM 1: The Lift System
	# Grabs the plate hidden inside the Lift node
	if has_node("Lift") and has_node("Lift/pressure_plate"):
		var lift_plate = $Lift/pressure_plate
		lift_plate.plate_activated.connect($Lift._on_pressure_plate_activated)
		print("✅ SYSTEM 1: Lift Plate connected to Lift.")
	else:
		print("❌ SYSTEM 1 ERROR: Can't find Lift or Lift/pressure_plate")

	# SYSTEM 2: The Arrow Trap System
	# Grabs the standalone plate on the floor and wires it to the dispenser
	if has_node("pressure_plate_arrows") and has_node("Arrow_dispenser"):
		var trap_plate = $pressure_plate_arrows
		trap_plate.plate_activated.connect($Arrow_dispenser._on_pressure_plate_activated)
		print("✅ SYSTEM 2: Trap Plate connected to Arrow Dispenser.")
	else:
		print("❌ SYSTEM 2 ERROR: Can't find 'trap_pressure_plate' or 'ArrowDispenser'. Check your spelling!")
