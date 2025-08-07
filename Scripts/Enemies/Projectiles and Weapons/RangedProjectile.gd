# RangedProjectile.gd
# A versatile projectile that can move in a straight line or home in on a target.
# Its behavior is determined by the parameters passed during initialization.
# ROOT NODE MUST BE AN Area2D.

class_name RangedProjectile
extends Area2D

@onready var notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D

# --- Core Stats ---
var speed: float = 250.0
var damage: float = 10.0
var direction: Vector2 = Vector2.RIGHT
var lifespan: float = 5.0 # Default lifespan, will be overridden

# --- Homing Properties ---
var homing_strength: float = 0.0 # 0.0 = no homing, > 0.0 = homing enabled
var target_node: Node2D = null

# --- State ---
var _was_on_screen: bool = false

# This function is now expanded to accept optional homing and lifespan parameters.
func initialize(p_start_pos: Vector2, p_direction: Vector2, p_speed: float, p_damage: float, p_lifespan: float = 5.0, p_homing_strength: float = 0.0, p_target: Node2D = null):
	global_position = p_start_pos
	direction = p_direction.normalized()
	speed = p_speed
	damage = p_damage
	lifespan = p_lifespan
	
	# Store the homing parameters
	homing_strength = p_homing_strength
	target_node = p_target
	
	# Point the projectile in its initial direction
	rotation = direction.angle()
	
	# --- SOLUTION: Create the timer here ---
	# This is now guaranteed to use the correct lifespan value passed from the enemy.
	get_tree().create_timer(lifespan).timeout.connect(queue_free)

func _ready():
	# Connect signals for efficient cleanup and damage.
	if is_instance_valid(notifier):
		notifier.screen_entered.connect(_on_screen_entered)
		notifier.screen_exited.connect(_on_screen_exited)
	else:
		push_warning("RangedProjectile is missing its VisibleOnScreenNotifier2D child.")
	
	body_entered.connect(_on_body_entered)
	
	# The failsafe timer is now created in initialize() to avoid a race condition.

func _physics_process(delta):
	# --- Simplified and Unified Movement Logic ---
	# 1. Homing: If there is a valid target, adjust the main direction vector towards it.
	if is_instance_valid(target_node) and homing_strength > 0.0:
		var direction_to_target = global_position.direction_to(target_node.global_position)
		# Slerp provides a smooth, curved turn towards the target.
		# The turning speed is controlled by homing_strength.
		direction = direction.slerp(direction_to_target, homing_strength * delta)

	# 2. Movement: Always move the projectile forward in its current direction.
	global_position += direction * speed * delta
	
	# 3. Rotation: Always face the direction of travel.
	rotation = direction.angle()

func _on_body_entered(body: Node2D):
	if body.is_in_group("player_char_group"):
		if body.has_method("take_damage"):
			body.take_damage(damage, self, {})
	
	queue_free()

func _on_screen_entered():
	# The projectile is now on screen, so it's safe to enable off-screen cleanup.
	_was_on_screen = true

func _on_screen_exited():
	# Only destroy the projectile if it was previously on screen.
	# This prevents projectiles spawned off-screen from being deleted instantly.
	if _was_on_screen:
		queue_free()
