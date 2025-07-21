class_name ThornProjectile
extends Area2D

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _direction: Vector2
var _speed: float = 250.0
var _damage: int
var _owner: PlayerCharacter
var _specific_stats: Dictionary

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats):
	_direction = p_direction
	rotation = _direction.angle()
	_owner = p_player_stats.get_parent()
	
	var damage_percent = float(p_stats.get(&"thorn_burst_damage_percentage", 1.0))
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")

	var base_damage = p_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage = final_damage	
	var projectile_scale = float(p_stats.get(&"thorn_projectile_scale", 1.0))
	sprite.scale = Vector2.ONE * projectile_scale
	collision_shape.scale = Vector2.ONE * projectile_scale
	
	lifetime_timer.wait_time = 0.4
	lifetime_timer.start()

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
		# FIX: Initialize as a typed array first, then populate it.
		# This prevents the type mismatch error when passing to take_damage().
		var weapon_tags: Array[StringName] = []
		if _specific_stats.has("tags"):
			weapon_tags = _specific_stats.get("tags")

		body.take_damage(_damage, _owner, {}, weapon_tags) # Now safely passing the correct type
		queue_free()
