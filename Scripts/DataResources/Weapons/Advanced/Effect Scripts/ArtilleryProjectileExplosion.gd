# File: res://Scripts/Weapons/Advanced/Turrets/ArtilleryProjectileExplosion.gd
class_name ArtilleryProjectileExplosion
extends Area2D

const BASE_SPRITE_DIAMETER = 250.0 # The pixel width of your base explosion animation sprite

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _specific_stats: Dictionary


func initialize(damage: int, radius: float, source_node: Node, attack_stats: Dictionary, p_weapon_stats: Dictionary):
	if collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = radius
	
	# Calculate visual scale based on the collision radius
	var visual_scale = (radius * 2) / BASE_SPRITE_DIAMETER
	animated_sprite.scale = Vector2.ONE * visual_scale
	
	animated_sprite.play("explode")
	animated_sprite.animation_finished.connect(queue_free)
	
	get_tree().create_timer(0.05).timeout.connect(_deal_damage.bind(damage, source_node, attack_stats, p_weapon_stats))

func _deal_damage(damage: int, source_node: Node, attack_stats: Dictionary, _p_weapon_stats: Dictionary):
	if not is_instance_valid(self): return
	
	for body in get_overlapping_bodies():
		if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
			var weapon_tags: Array[StringName] = []
			if _specific_stats.has("tags"):
				weapon_tags = _specific_stats.get("tags")
			body.take_damage(damage, source_node, attack_stats, weapon_tags) # Pass tags
