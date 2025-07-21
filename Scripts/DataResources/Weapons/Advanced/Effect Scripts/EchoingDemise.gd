# File: EchoingDemise.gd
# Attach to: EchoingDemise.tscn
# --------------------------------------------------------------------
class_name EchoingDemise
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	var damage_percent = float(p_stats.get("echoing_demise_damage_percentage", 2.0))
	var weapon_tags: Array[StringName] = p_stats.get("tags", [])
	var base_damage = p_player_stats.get_calculated_base_damage(damage_percent)
	var damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	
	var base_radius = float(p_stats.get("echoing_demise_radius", 150.0))
	var global_aoe_mult = p_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	var final_radius = base_radius * global_aoe_mult
	
	(collision_shape.shape as CircleShape2D).radius = final_radius
	
	var sprite_texture = animated_sprite.sprite_frames.get_frame_texture("explode", 0)
	if is_instance_valid(sprite_texture):
		var texture_size = sprite_texture.get_width()
		if texture_size > 0:
			animated_sprite.scale = Vector2.ONE * (final_radius * 2 / texture_size)
			
	animated_sprite.play("explode")
	animated_sprite.animation_finished.connect(queue_free)
	
	call_deferred("_deal_damage", damage, p_player_stats.get_parent(), weapon_tags)

func _deal_damage(damage: int, owner: Node, weapon_tags: Array[StringName]):
	# FIX: Replace the physics_frame wait with a short timer to ensure the physics server updates.
	await get_tree().create_timer(0.05).timeout
	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body is BaseEnemy and not body.is_dead():
			body.take_damage(damage, owner, {}, weapon_tags)
