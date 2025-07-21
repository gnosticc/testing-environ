# File: WaterBall.gd
# Attach to: WaterBall.tscn (root Area2D)
# --------------------------------------------------------------------
class_name WaterBall
extends Area2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

const GEYSER_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/GeyserExplosion.tscn")

var _direction: Vector2
var _speed: float = 180.0
var _damage: int
var _enemies_hit: Array[Node] = []
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats

func _ready():
	lifetime_timer.timeout.connect(_on_lifetime_expired)
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats):
	_direction = p_direction.normalized()
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	
	var damage_percent = float(p_stats.get("water_ball_damage_percentage", 1.0))
	if p_stats.get("has_riptide", false):
		damage_percent *= 1.5
	
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage = final_damage
	
	var base_scale = float(p_stats.get("water_ball_scale", 1.0))
	var global_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	self.scale = Vector2.ONE * base_scale * global_size_mult
	
	lifetime_timer.wait_time = float(p_stats.get("water_ball_lifetime", 1.5))
	lifetime_timer.start()
	rotation = _direction.angle()
	
	sprite.play("default")

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not body.is_dead() and not _enemies_hit.has(body):
		_enemies_hit.append(body)
		var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
		body.take_damage(_damage, _owner_player_stats.get_parent(), {}, weapon_tags)
		
		# FIX: The projectile no longer destroys itself when spawning a geyser, allowing it to pierce.
		if _specific_stats.get("has_geyser", false):
			call_deferred("_spawn_geyser")
			# The queue_free() call has been removed from here.

func _on_lifetime_expired():
	if _specific_stats.get("has_geyser", false):
		# FIX: Defer the geyser spawn
		call_deferred("_spawn_geyser")
	queue_free()

func _spawn_geyser():
	if not is_instance_valid(self): return # Safety check
	var geyser = GEYSER_SCENE.instantiate()
	get_tree().current_scene.add_child(geyser)
	geyser.global_position = self.global_position
	geyser.initialize(_specific_stats, _owner_player_stats)
