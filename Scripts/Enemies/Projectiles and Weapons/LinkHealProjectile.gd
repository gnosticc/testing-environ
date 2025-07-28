# LinkHealProjectile.gd
# A homing projectile that seeks out a designated wounded enemy to heal it.
# Spawned by the OnDeathBehaviorHandler for enemies with the "link" tag.
# VERSION 1.1: Corrected rotation logic, fixed missing variable, and added a visual tween.

class_name LinkHealProjectile
extends Area2D

# --- Properties ---
var target_enemy: BaseEnemy
var owner_enemy: BaseEnemy # The enemy that fired this projectile
var heal_amount: float = 0.0
var speed: float = 300.0
var turn_rate: float = 3.0 # Radians per second

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visible_on_screen_notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D
@onready var sprite: Sprite2D = $Sprite2D # Assuming your sprite node is named Sprite2D

func _ready():
	body_entered.connect(_on_body_entered)
	visible_on_screen_notifier.screen_exited.connect(queue_free)
	
	# --- SOLUTION: Add a flashing tween ---
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_loops()
	tween.tween_property(sprite, "modulate", Color.LIGHT_GREEN, 0.3)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.3)
	# --- END SOLUTION ---

func _physics_process(delta: float):
	# If the target is no longer valid (e.g., it was killed), destroy the projectile.
	if not is_instance_valid(target_enemy) or target_enemy.is_dead():
		queue_free()
		return

	# --- Homing Logic ---
	var direction_to_target = global_position.direction_to(target_enemy.global_position)
	# --- SOLUTION: Use lerp_angle for smooth rotation ---
	rotation = lerp_angle(rotation, direction_to_target.angle(), turn_rate * delta)
	
	# Move forward in the current direction.
	var velocity = Vector2.RIGHT.rotated(rotation) * speed
	global_position += velocity * delta

# Public function called by the OnDeathBehaviorHandler to set up the projectile.
func initialize(p_start_position: Vector2, p_target: BaseEnemy, p_heal_amount: float, p_owner: BaseEnemy):
	global_position = p_start_position
	target_enemy = p_target
	heal_amount = p_heal_amount
	owner_enemy = p_owner # Set the owner
	
	# Immediately point towards the initial target position.
	rotation = global_position.direction_to(target_enemy.global_position).angle()

func _on_body_entered(body: Node2D):
	# Check if we've hit our specific target.
	if body == target_enemy:
		if body.has_method("take_damage"): # We'll reuse take_damage with a negative value for healing
			body.take_damage(-heal_amount, owner_enemy)
		
		# Destroy the projectile after it hits its target.
		queue_free()
