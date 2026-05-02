extends Node3D

@export var button: Node3D
@export var step_area: Area3D # The Area3D you stand on
@export var is_step_activated: bool = false

@export var closed_angle: float = 0.0
@export var open_angle: float = -90.0 # -90 swings it down
@export var rotation_speed: float = 5.0
@export var stop_threshold_deg: float = 0.5

var target_angle_rad: float = 0.0
var should_change: bool = false

func _ready():
	# Initial position
	target_angle_rad = deg_to_rad(closed_angle)
	
	# Connect to button if assigned
	if button:
		button.pressed.connect(_on_toggle_trapdoor)
		
	# Connect to Area3D if assigned and enabled
	if is_step_activated and step_area:
		step_area.body_entered.connect(_on_step_entered)

func _process(delta: float) -> void:
	if should_change:
		# Use rotation.x for a trapdoor swing
		rotation.x = lerp_angle(rotation.x, target_angle_rad, rotation_speed * delta)

		# Stop moving when close enough
		if abs(angle_difference(rotation.x, target_angle_rad)) < deg_to_rad(stop_threshold_deg):
			rotation.x = target_angle_rad
			should_change = false

func _on_toggle_trapdoor():
	# Toggles between open and closed
	if target_angle_rad == deg_to_rad(closed_angle):
		target_angle_rad = deg_to_rad(open_angle)
	else:
		target_angle_rad = deg_to_rad(closed_angle)
	should_change = true

func _on_step_entered(body):
	if body is CharacterBody3D:
		target_angle_rad = deg_to_rad(open_angle)
		should_change = true
