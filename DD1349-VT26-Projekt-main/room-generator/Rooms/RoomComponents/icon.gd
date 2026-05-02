extends Sprite3D

var coins = 5
var playerName = "robot"
var hearts = 3.5
const SPEED = 2
var x = coins + SPEED
var isGodotAwesome = true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	if Input.is_action_pressed("ui_left"):
		rotate_y(deg_to_rad(hearts))
	elif Input.is_action_pressed("ui_right"):
		rotate_y(-delta*hearts)
	elif Input.is_action_pressed("ui_up"):
		sayNigga()
func sayNigga():
	print("hello ")
