# File: res://Scripts/Weapons/Projectiles/GaleWaveProjectile.gd
# This script controls the energy wave from the Blade of the Gale upgrade.

class_name GaleWaveProjectile
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _damage: int = 20
var _speed: float = 400.0
var _direction: Vector2 = Vector2.RIGHT
var _enemies_hit: Array[Node2D] = [] # To prevent hitting the same enemy multiple times
var _owner_player_stats: PlayerStats
var _specific_stats: Dictionary

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func setup(p_damage: int, p_direction: Vector2, p_player_stats: PlayerStats, p_weapon_stats: Dictionary):
	_damage = p_damage
	_direction = p_direction.normalized()
	rotation = _direction.angle()
	_owner_player_stats = p_player_stats
	_specific_stats = p_weapon_stats # Store the stats
	
	if is_instance_valid(p_player_stats):
		_speed *= p_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	
	lifetime_timer.start()
	animated_sprite.play("fly")


func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_body_entered(body: Node2D):
	if body.is_in_group("enemies") and body is BaseEnemy and not _enemies_hit.has(body):
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return
		
		# CORRECTED: Use the stored stats to get the tags.
		var weapon_tags: Array[StringName] = []
		if _specific_stats.has("tags"):
			weapon_tags = _specific_stats.get("tags")
			
		enemy_target.take_damage(_damage, _owner_player_stats.get_parent(), {}, weapon_tags)
		_enemies_hit.append(enemy_target)
		# This is a piercing projectile, so it does not queue_free() on hit.
