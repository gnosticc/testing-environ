# Path: res://Scripts/Weapons/Advanced/SplinterProjectile.gd
# ===================================================================
class_name SplinterProjectile
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _direction: Vector2
var _speed: float = 200.0
var _damage: int
var _owner_player: PlayerCharacter
var _specific_stats: Dictionary

func _ready():
	# FIX: Disable collision shape initially to prevent instant collision.
	collision_shape.disabled = true
	# Create a timer to enable collision shortly after spawning.
	get_tree().create_timer(0.15, true, false, true).timeout.connect(Callable(collision_shape, "set_disabled").bind(false))

	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_player_stats: PlayerStats, p_owner_player: PlayerCharacter, p_damage: int, p_weapon_stats: Dictionary):
	_direction = p_direction
	_owner_player = p_owner_player
	_damage = p_damage
	_specific_stats = p_weapon_stats # Store the stats
	rotation = _direction.angle()
	
	_speed *= p_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	
	lifetime_timer.start()
	animated_sprite.play("fly")

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
		var weapon_tags: Array[StringName] = []
		if _specific_stats.has("tags"):
			weapon_tags = _specific_stats.get("tags")
		body.take_damage(_damage, _owner_player, {}, weapon_tags) # Pass tags
		call_deferred("queue_free")
