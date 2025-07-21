# File: LuringPrismProjectile.gd
# Attach to: LuringPrismProjectile.tscn (root Area2D)
# --------------------------------------------------------------------
class_name LuringPrismProjectile
extends Area2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

const RING_OF_SHARDS_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/RingOfShards.tscn")

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _target_enemy: BaseEnemy
var _direction: Vector2
var _speed: float = 600.0

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_target: BaseEnemy, p_stats: Dictionary, p_player_stats: PlayerStats):
	_target_enemy = p_target
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats

	# --- Projectile Speed Logic ---
	_speed *= _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	
	# --- Projectile Scale Logic ---
	var base_scale = float(_specific_stats.get("projectile_scale", 1.0))
	var global_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	var final_scale = base_scale * global_size_mult
	self.scale = Vector2.ONE * final_scale
	
	lifetime_timer.start()
	sprite.play("fly") # Assuming a "fly" animation

func _physics_process(delta: float):
	if is_instance_valid(_target_enemy) and not _target_enemy.is_dead():
		_direction = (_target_enemy.global_position - global_position).normalized()
	
	global_position += _direction * _speed * delta
	rotation = _direction.angle()

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not body.is_dead():
		var owner_player = _owner_player_stats.get_parent()
		var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
		var damage_percent = float(_specific_stats.get("impact_damage_percentage", 1.0))
		var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
		var damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
		
		body.take_damage(damage, owner_player, {}, weapon_tags)
		
		# Defer the function call that modifies the physics world.
		call_deferred("_spawn_ring_and_destroy")
		
func _spawn_ring_and_destroy():
	if is_instance_valid(RING_OF_SHARDS_SCENE):
		var ring = RING_OF_SHARDS_SCENE.instantiate()
		get_tree().current_scene.add_child(ring)
		ring.global_position = self.global_position
		if ring.has_method("initialize"):
			ring.initialize(_specific_stats, _owner_player_stats)
	
	queue_free()
