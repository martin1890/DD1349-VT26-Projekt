extends Area3D

@export var speed: float = 25.0
@export var lifetime: float = 3.0

# The safety switch: arrows start turned off
var is_flying: bool = false 

func _ready():
	body_entered.connect(_on_body_entered)

# This custom function will be called by the dispenser to launch the arrow
func launch():
	print("🚀 ", name, " received launch command! Moving now.")
	is_flying = true
	
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func _physics_process(delta):
	# Only move forward if the dispenser launched us
	if is_flying:
		global_position -= global_transform.basis.z * speed * delta

func _on_body_entered(body):
	# Ignore collisions if the arrow hasn't been fired yet
	if not is_flying:
		return
		
	var is_player = body.is_in_group("player") or (body.owner and body.owner.is_in_group("player"))
	
	if is_player:
		print("🎯 OUCH! Steve took an arrow to the knee!")
		queue_free()
	elif not body.is_in_group("dispenser"): 
		queue_free()
