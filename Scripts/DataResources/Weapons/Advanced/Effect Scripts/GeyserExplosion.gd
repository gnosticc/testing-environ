# File: GeyserExplosion.gd
# Attach to: GeyserExplosion.tscn (root Area2D)
# --------------------------------------------------------------------
class_name GeyserExplosion
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _specific_stats: Dictionary

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_stats
	var damage_percent = float(p_stats.get("geyser_damage_percentage", 0.75))
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	var base_damage = p_player_stats.get_calculated_base_damage(damage_percent)
	var damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	
	var radius = float(p_stats.get("geyser_radius", 60.0))
	(collision_shape.shape as CircleShape2D).radius = radius
	
	# Scale sprite to match radius
	var sprite_texture = animated_sprite.sprite_frames.get_frame_texture("erupt", 0)
	if is_instance_valid(sprite_texture):
		var texture_size = sprite_texture.get_width()
		if texture_size > 0:
			animated_sprite.scale = Vector2.ONE * (radius * 2 / texture_size)
			
	animated_sprite.play("erupt")
	animated_sprite.animation_finished.connect(queue_free)
	
	call_deferred("_deal_damage", damage, p_player_stats.get_parent())

func _deal_damage(damage: int, owner: Node):
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		if body is BaseEnemy and not body.is_dead():
			var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
			body.take_damage(damage, owner, {}, weapon_tags)
