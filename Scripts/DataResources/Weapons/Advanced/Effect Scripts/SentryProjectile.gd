# File: res://Scripts/Weapons/Advanced/Turrets/SentryProjectile.gd
class_name SentryProjectile
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var direction: Vector2
var speed: float
var damage: int
var owner_player: PlayerCharacter
var _specific_stats: Dictionary



func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_target: BaseEnemy, p_stats: Dictionary, p_player_stats: PlayerStats):
	owner_player = p_player_stats.get_parent()
	
	if is_instance_valid(p_target):
		direction = (p_target.global_position - global_position).normalized()
	else:
		direction = Vector2.RIGHT.rotated(randf_range(0, TAU)) # Failsafe direction
		
	rotation = direction.angle()
	
	var base_scale = float(p_stats.get("sentry_projectile_scale", 1.0))
	self.scale = Vector2.ONE * base_scale
	
	speed = float(p_stats.get("sentry_projectile_speed", 400.0)) * p_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	
	var damage_percent = float(p_stats.get("sentry_damage_percent", 0.8)) * float(p_stats.get("turret_damage_mult", 1.0))
	var weapon_tags: Array[StringName] = []
	if p_stats.has("tags"):
		weapon_tags = p_stats.get("tags")
	var base_damage = p_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	damage = int(final_damage)
	
	lifetime_timer.start()

func _physics_process(delta: float):
	global_position += direction * speed * delta

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
		var weapon_tags: Array[StringName] = []
		if _specific_stats.has("tags"):
			weapon_tags = _specific_stats.get("tags")
		body.take_damage(damage, owner_player, {}, weapon_tags) # Pass tags
		queue_free()
