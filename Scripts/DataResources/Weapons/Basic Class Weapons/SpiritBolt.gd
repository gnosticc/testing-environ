# SpiritBolt.gd
# A simple projectile fired by summoned spirits.
class_name SpiritBolt
extends Area2D

var speed: float = 400.0
var damage: int = 5
var direction: Vector2 = Vector2.RIGHT
var owner_player: PlayerCharacter = null

@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer")

func _ready():
	if not is_instance_valid(lifetime_timer):
		print("ERROR (SpiritBolt): LifetimeTimer is missing!"); call_deferred("queue_free"); return
	
	lifetime_timer.timeout.connect(queue_free)
	lifetime_timer.start()
	
	self.rotation = direction.angle()
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float):
	global_position += direction * speed * delta

func _on_body_entered(body: Node2D):
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage, owner_player)
		queue_free()
	elif body.is_in_group("world_obstacles"):
		queue_free()
