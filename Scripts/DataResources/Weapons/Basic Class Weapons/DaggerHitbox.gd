# DaggerHitbox.gd
# REFACTORED: The initialize function now accepts a scale parameter to allow
# for upgrades that increase the attack's area of effect.
class_name DaggerHitbox
extends Area2D

@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer")
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionPolygon2D")

var _damage_to_deal: int = 0
var _owner_player: PlayerCharacter = null
var _enemies_hit_this_attack: Array[Node2D] = []

func _ready():
	if not is_instance_valid(lifetime_timer):
		print("ERROR (DaggerHitbox): LifetimeTimer is missing!"); queue_free(); return
	
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_damage: int, p_owner_player: PlayerCharacter, p_scale: Vector2, lifetime: float = 0.1):
	_damage_to_deal = p_damage
	_owner_player = p_owner_player
	lifetime_timer.wait_time = lifetime
	lifetime_timer.start()
	
	# Apply the scale to the hitbox itself
	if is_instance_valid(collision_shape):
		collision_shape.scale = p_scale

func _on_body_entered(body: Node2D):
	if not is_instance_valid(body) or _enemies_hit_this_attack.has(body):
		return
		
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		_enemies_hit_this_attack.append(body)
		body.take_damage(_damage_to_deal, _owner_player)
