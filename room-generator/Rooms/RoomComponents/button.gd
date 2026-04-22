extends StaticBody3D

signal pressed

func interact():
	print("Button was pressed!")
	emit_signal("pressed")
	# Add animation or sound effects here
