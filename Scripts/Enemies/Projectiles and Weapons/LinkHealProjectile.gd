# LinkHealProjectile.gd
# A projectile that seeks out a designated wounded enemy to heal it via a curved path.
# VERSION 1.3: Reworked movement to use a quadratic Bezier curve for an arcing path.

class_name LinkHealProjectile
extends Area2D

# --- Properties ---
var target_enemy: BaseEnemy
var heal_amount: float = 0.0
var speed: float = 200.0

# --- Bezier Curve Properties ---
var _start_pos: Vector2
var _end_pos: Vector2
var _control_point: Vector2
var _travel_duration: float
var _time: float = 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visible_on_screen_notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D
@onready var sprite: Sprite2D = $Sprite2D

func _ready():
	body_entered.connect(_on_body_entered)
	visible_on_screen_notifier.screen_exited.connect(queue_free)
	
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_loops()
	tween.tween_property(sprite, "modulate", Color.LIGHT_GREEN, 0.3)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.3)

func _physics_process(delta: float):
	if not is_instance_valid(target_enemy) or target_enemy.is_dead():
		queue_free()
		return

	# Update the end position to track the moving target
	_end_pos = target_enemy.global_position
	
	# Move along the curve
	_time += delta
	var t = min(1.0, _time / _travel_duration)
	
	# Quadratic Bezier curve formula
	global_position = _start_pos.lerp(_control_point, t).lerp(_control_point.lerp(_end_pos, t), t)
	
	# Point towards the next position on the curve to simulate rotation
	var next_t = min(1.0, (_time + delta) / _travel_duration)
	var next_pos = _start_pos.lerp(_control_point, next_t).lerp(_control_point.lerp(_end_pos, next_t), next_t)
	rotation = global_position.direction_to(next_pos).angle()

	if t >= 1.0:
		_apply_heal_and_destroy()

# Public function called by the OnDeathBehaviorHandler to set up the projectile.
func initialize(p_start_position: Vector2, p_target: BaseEnemy, p_heal_amount: float, p_control_point: Vector2):
	global_position = p_start_position
	target_enemy = p_target
	heal_amount = p_heal_amount
	
	_start_pos = p_start_position
	_end_pos = p_target.global_position
	_control_point = p_control_point
	
	# Estimate travel duration based on straight-line distance
	var distance = _start_pos.distance_to(_end_pos)
	if speed > 0:
		_travel_duration = distance / speed

func _on_body_entered(body: Node2D):
	if body == target_enemy:
		_apply_heal_and_destroy()

func _apply_heal_and_destroy():
	if is_instance_valid(target_enemy):
		if target_enemy.has_method("heal"):
			target_enemy.heal(heal_amount)
	queue_free()
