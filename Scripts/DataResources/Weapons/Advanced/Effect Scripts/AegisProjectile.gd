# File: res://Scripts/Weapons/Advanced/Turrets/AegisProjectile.gd
# RE-ADDED: This script controls the simple projectile for the Aegis Protector.
class_name AegisProjectile
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var direction: Vector2
var speed: float = 500.0
var damage: int
var owner_player: PlayerCharacter
var _specific_stats: Dictionary

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats):
	direction = p_direction.normalized()
	owner_player = p_player_stats.get_parent()
	rotation = direction.angle()
	
	var base_scale = float(p_stats.get("aegis_projectile_scale", 1.0))
	self.scale = Vector2.ONE * base_scale
	
	# Speed is not modified by player stats for this projectile, it's a fixed short burst.
	
	var damage_percent = float(p_stats.get("aegis_damage_percent", 0.7)) * float(p_stats.get("turret_damage_mult", 1.0))
	var weapon_tags: Array[StringName] = p_stats.get("tags", [])
	var base_damage = p_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	damage = int(final_damage)
	
	# Short lifetime for a point-blank attack
	lifetime_timer.wait_time = 0.5 
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
