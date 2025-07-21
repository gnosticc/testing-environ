# File: res://Scripts/Weapons/Advanced/Effect Scripts/ChromaticIceShard.gd
# Attach to: ChromaticIceShard.tscn (Root Area2D)
# Purpose: Controls the behavior of a single ice shard projectile.

class_name ChromaticIceShard
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _direction: Vector2
var _speed: float
var _damage: int
var _pierce_count: int
var _enemies_hit: Array[Node] = []
var _owner_player_stats: PlayerStats
var _specific_stats: Dictionary

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats):
	_direction = p_direction.normalized()
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	
	var damage_percent = float(p_stats.get("ice_shard_damage_percentage", 0.7))
	var weapon_tags: Array[StringName] = p_stats.get("tags", [])
	var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage = final_damage
	
	_speed = float(p_stats.get("ice_shard_speed", 400.0)) * _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	_pierce_count = 2 if p_stats.get(&"has_shatterstorm", false) else 0
	
	var base_scale = float(p_stats.get("ice_shard_projectile_scale", 1.0))
	var global_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	self.scale = Vector2.ONE * base_scale * global_size_mult
	
	rotation = _direction.angle()
	lifetime_timer.start()
	animated_sprite.play("fly")

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not body.is_dead() and not _enemies_hit.has(body):
		_enemies_hit.append(body)
		var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
		body.take_damage(_damage, _owner_player_stats.get_parent(), {}, weapon_tags)
		
		if _pierce_count <= 0:
			queue_free()
		else:
			_pierce_count -= 1
