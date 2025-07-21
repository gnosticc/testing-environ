# File: VolatileEssenceExplosion.gd
# Attach to: VolatileEssenceExplosion.tscn
# --------------------------------------------------------------------
class_name VolatileEssenceExplosion
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func initialize(damage: int, source_node: Node, p_weapon_stats: Dictionary):
	var base_radius = float(p_weapon_stats.get("volatile_essence_radius", 40.0))
	var global_aoe_mult = source_node.player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	var final_radius = base_radius * global_aoe_mult
	
	if collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = final_radius
	
	var sprite_texture = animated_sprite.sprite_frames.get_frame_texture("default", 0)
	if is_instance_valid(sprite_texture):
		var texture_size = sprite_texture.get_width()
		if texture_size > 0:
			animated_sprite.scale = Vector2.ONE * (final_radius * 2 / texture_size)
			
	animated_sprite.play("default")
	animated_sprite.animation_finished.connect(queue_free)
	
	call_deferred("_deal_damage", damage, source_node, p_weapon_stats)

func _deal_damage(damage: int, owner: Node, weapon_stats: Dictionary):
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		if body is BaseEnemy and not body.is_dead():
			var weapon_tags: Array[StringName] = weapon_stats.get("tags", [])
			body.take_damage(damage, owner, {}, weapon_tags)
