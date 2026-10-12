extends Node3D

@onready var door_body = $DoorBody
@onready var hinge = $HingeJoint3D

var time_since_interact: float = 0.0
var original_rotation: float = 0.0

func _ready():
	# The HingeJoint3D itself doesn't report angle easily, but we can measure the DoorBody's local rotation relative to the frame
	original_rotation = door_body.rotation.y
	
	# We configure the Hinge Motor. It will act as a "spring" to close the door.
	# We leave it disabled by default until the door needs to close.
	hinge.set("motor/enable", false)
	hinge.set("motor/target_velocity", 0.0)
	hinge.set("motor/max_impulse", 0.5)

func _physics_process(delta):
	# Increase the idle timer
	time_since_interact += delta
	
	# Calculate how far the door is currently open
	var current_angle = door_body.rotation.y - original_rotation
	var is_open = abs(current_angle) > 0.05
	
	# If nobody has touched the door in 1.0 second, and it's open, turn on the closing spring!
	if time_since_interact > 1.0 and is_open:
		hinge.set("motor/enable", true)
		
		# If the angle is positive, motor needs negative velocity. If negative, positive velocity.
		var close_speed = 1.0
		if current_angle > 0:
			hinge.set("motor/target_velocity", -close_speed)
		else:
			hinge.set("motor/target_velocity", close_speed)
	else:
		# Turn off the motor so the player/enemy can push it freely without resistance!
		hinge.set("motor/enable", false)

# We call this from player.gd and capsule_enemy.gd whenever they touch or drag the door!
func register_interaction():
	time_since_interact = 0.0
	door_body.sleeping = false
