# LesserSpiritProjectile.gd
# Attached to the root Area2D of LesserSpiritProjectile.tscn
class_name LesserSpiritProjectile
extends Area2D

var speed: float = 250.0
var damage: int = 8
var direction: Vector2 = Vector2.RIGHT
var final_applied_scale: Vector2 = Vector2(1.0, 1.0)

@onready var visual: AnimatedSprite2D = get_node_or_null("Visual") as AnimatedSprite2D # Or AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer") as Timer

func _ready():
	if not is_instance_valid(visual): print("ERROR (LesserSpiritProjectile): Visual node missing.")
	if not is_instance_valid(collision_shape): print("ERROR (LesserSpiritProjectile): CollisionShape2D node missing.")
	if not is_instance_valid(lifetime_timer):
		print("ERROR (LesserSpiritProjectile): LifetimeTimer node missing!"); call_deferred("queue_free"); return
	else:
		# Lifetime can also be affected by PlayerStats' effect_duration_multiplier if desired
		# For now, fixed lifetime.
		lifetime_timer.timeout.connect(queue_free) # Using built-in queue_free
		lifetime_timer.start()
	
	# Assume projectile sprite faces RIGHT by default
	# If it faces LEFT, use: rotation = direction.angle() - PI
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	
	_apply_visual_scale()

func _physics_process(delta: float):
	global_position += direction * speed * delta

func setup(p_direction: Vector2, p_damage: int, p_speed: float, p_scale_vector: Vector2):
	direction = p_direction.normalized() if p_direction.length_squared() > 0 else Vector2.RIGHT
	damage = p_damage
	speed = p_speed
	final_applied_scale = p_scale_vector

	# Apply initial rotation and scale if node is ready, otherwise _ready will handle it
	if is_inside_tree():
		if direction != Vector2.ZERO: rotation = direction.angle()
		_apply_visual_scale()

func _apply_visual_scale():
	if is_instance_valid(visual): visual.scale = final_applied_scale
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale

func _on_body_entered(body: Node2D):
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free() # Destroy projectile on hit
	elif body.is_in_group("world_obstacles"): # If you have obstacles
		queue_free()
