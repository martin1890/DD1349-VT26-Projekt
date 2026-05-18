extends RigidBody3D

func _ready() -> void:
	# Connect the Area3D's body_entered signal to this script
	# Replace $Area3D with the actual name of your Area3D node
	$Area3D.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	# Check if the object we hit is the player
	# (Assuming your player script has 'class_name Player' or is named "Player")
	if body.is_in_group("player") or body.name == "Player":
		if body.has_method("take_damage"):
			body.take_damage(25) # Deal 25 damage
		else:
			print("Hit the player, but player has no take_damage method!")
			# Alternative: body.queue_free() to instantly destroy player
