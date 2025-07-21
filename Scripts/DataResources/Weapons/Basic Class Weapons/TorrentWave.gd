# File: res://Scripts/Weapons/Projectiles/TorrentWave.gd
# REVISED: Now handles lifetime and visual flipping correctly.
class_name TorrentWave
extends Area2D

@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var _damage: int
var _speed: float = 200.0
var _direction: Vector2
var _enemies_hit: Array[Node2D] = []
var _specific_stats: Dictionary


func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(damage: int, direction: Vector2, p_player_stats: PlayerStats, p_weapon_stats: Dictionary):
	_damage = damage
	_direction = direction.normalized()
	_specific_stats = p_weapon_stats # Store the stats
	rotation = _direction.angle()
	
	# NEW: Set vertical flip based on direction
	if _direction.y > 0:
		animated_sprite.flip_v = true

	if is_instance_valid(p_player_stats):
		_speed *= p_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)

	# NEW: Set fixed lifetime
	lifetime_timer.wait_time = 1.5
	lifetime_timer.start()

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and is_instance_valid(body) and not body.is_dead() and not _enemies_hit.has(body):
		var weapon_tags: Array[StringName] = []
		if _specific_stats.has("tags"):
			weapon_tags = _specific_stats.get("tags")
		body.take_damage(_damage, get_parent(), {}, weapon_tags) # Pass tags
		_enemies_hit.append(body)
