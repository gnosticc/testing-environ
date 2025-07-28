# CreeperBullet.gd
# A simple projectile spawned by enemies with the "creeper" on-death tag.
# VERSION 1.2: Fixed error by using process_mode instead of the nonexistent 'enabled' property.

class_name CreeperBullet extends Area2D

var direction: Vector2 = Vector2.UP
var speed: float = 200.0
var damage: float = 5.0

# This timer gives the bullet a moment to fly onto the screen before the
# VisibleOnScreenNotifier2D is allowed to delete it.
const CULLING_GRACE_PERIOD = 0.5 # seconds

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visible_on_screen_notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D
@onready var grace_timer: Timer = $GraceTimer

func _ready():
	body_entered.connect(_on_body_entered)
	visible_on_screen_notifier.screen_exited.connect(queue_free)
	grace_timer.timeout.connect(_on_grace_timer_timeout)
	
	# --- SOLUTION: Use process_mode to disable the notifier ---
	# Start disabled, will be enabled by the timer.
	visible_on_screen_notifier.process_mode = Node.PROCESS_MODE_DISABLED
	# --- END SOLUTION ---

func _physics_process(delta: float):
	# Move the bullet in its set direction.
	global_position += direction * speed * delta

# This public function is called by the OnDeathBehaviorHandler to set the bullet's properties.
func initialize(p_start_position: Vector2, p_direction: Vector2, p_speed: float, p_damage: float):
	global_position = p_start_position
	direction = p_direction.normalized()
	speed = p_speed
	damage = p_damage
	
	# Point the sprite in the direction of movement (assuming sprite points up by default)
	rotation = direction.angle() + deg_to_rad(90)
	
	# Start the grace period timer.
	grace_timer.wait_time = CULLING_GRACE_PERIOD
	grace_timer.start()

func _on_body_entered(body: Node2D):
	# Check if the body we hit is the player.
	if body.is_in_group("player_char_group"):
		if body.has_method("take_damage"):
			body.take_damage(damage, null) # Pass null as the attacker for now
		
		# Destroy the bullet after it hits the player.
		queue_free()

func _on_grace_timer_timeout():
	# --- SOLUTION: Use process_mode to re-enable the notifier ---
	# The grace period is over. It's now safe to enable the screen notifier for culling.
	visible_on_screen_notifier.process_mode = Node.PROCESS_MODE_INHERIT
	# --- END SOLUTION ---
