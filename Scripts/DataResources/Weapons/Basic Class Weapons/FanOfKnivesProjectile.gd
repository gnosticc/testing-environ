# ======================================================================
# 2. NEW SCENE SCRIPT: FanOfKnivesProjectile.gd
# A simple projectile script for the spectral knives.
# Path: res://Scripts/Weapons/Projectiles/FanOfKnivesProjectile.gd
# ======================================================================

class_name FanOfKnivesProjectile
extends Area2D

var _damage: int = 1
var _speed: float = 250.0
var _direction: Vector2 = Vector2.RIGHT

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func setup(p_damage: int, p_direction: Vector2, p_player_stats: PlayerStats):
	_damage = p_damage
	_direction = p_direction.normalized()
	rotation = _direction.angle()
	
	# Optional: Scale projectile speed with player stats
	if is_instance_valid(p_player_stats):
		_speed *= p_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)

	lifetime_timer.start()
	if is_instance_valid(animated_sprite):
		animated_sprite.play("default") # Assuming a "default" animation for the knife

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_body_entered(body: Node2D):
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(_damage)
		queue_free() # Destroy on first hit
	elif body.is_in_group("world_obstacles"):
		queue_free()
