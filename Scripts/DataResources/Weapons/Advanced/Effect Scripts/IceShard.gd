# File: IceShard.gd
# Attach to: IceShard.tscn (root Area2D)
# --------------------------------------------------------------------
class_name IceShard
extends Area2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _direction: Vector2
var _speed: float = 400.0
var _damage: int
var _pierce_count: int = 0
var _enemies_hit: Array[Node] = []
var _owner_player_stats: PlayerStats
var _specific_stats: Dictionary

func _ready():
	# FIX: Connect the body_entered signal to handle collisions.
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats):
	_direction = p_direction.normalized()
	_owner_player_stats = p_player_stats
	_specific_stats = p_stats
	
	var damage_percent = float(p_stats.get("ice_shard_damage_percentage", 0.5))
	# Riptide only affects water balls, so the check is removed from here.
	
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage = final_damage	
	_pierce_count = 1 if p_stats.get("has_hoarfrost", false) else 0
	
	var base_scale = float(p_stats.get("ice_shard_scale", 1.0))
	var global_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	self.scale = Vector2.ONE * base_scale * global_size_mult
	
	rotation = _direction.angle()
	get_tree().create_timer(2.0).timeout.connect(queue_free)
	
	# FIX: Play the animation.
	sprite.play("default") # Assuming a "default" animation for the shard

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
