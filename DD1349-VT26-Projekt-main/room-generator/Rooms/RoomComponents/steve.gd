extends CharacterBody3D

const SPEED = 5.0
const CLIMB_SPEED = 3.0
const JUMP_VELOCITY = 4.5

var is_climbing = false

@onready var climb_ray = $ClimbableWallDetector # Adjust path if needed
@onready var ray = $Camera3D/RayCast3D

func _physics_process(delta: float) -> void:
	if is_climbing:
		handle_climb_movement(delta)
	else:
		handle_ground_movement(delta)

	move_and_slide()

func handle_ground_movement(delta):
	# Add gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get input direction
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

func handle_climb_movement(_delta):
	# Check if we are still facing a wall
	if not climb_ray.is_colliding():
		# If we lose the wall, we stop climbing
		# You can either call exit_climb() to fall, 
		# or just block upward movement. Let's exit:
		exit_climb()
		return

	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	var vertical_move = Vector3.UP * -input_dir.y 
	var horizontal_move = transform.basis.x * input_dir.x
	
	var climb_direction = (vertical_move + horizontal_move).normalized()
	
	# SAFETY CHECK: If moving UP, check if there is still a wall ahead
	# This prevents the "pop-off" at the very top edge
	if input_dir.y < 0 and not climb_ray.is_colliding():
		velocity.y = 0
	else:
		velocity = climb_direction * CLIMB_SPEED
		
func _input(event):
	# Toggle Climbing with "G"
	if event.is_action_pressed("climb"):
		if is_climbing:
			exit_climb()
		else:
			attempt_climb()

	# Existing interaction logic for "E"
	if event.is_action_pressed("interact"):
		print("Pressed E")
		if ray.is_colliding():
			print("Colliding")
			var collider = ray.get_collider()
			if collider.has_method("interact"):
				collider.interact()

func attempt_climb():
	if climb_ray.is_colliding():
		var collider = climb_ray.get_collider()
		if collider.is_in_group("climbable"):
			is_climbing = true
			velocity = Vector3.ZERO # Stop momentum when sticking

func exit_climb():
	is_climbing = false
	# Optional: Give a tiny push away from the wall so you don't 
	# immediately re-trigger the raycast if you're spamming G
