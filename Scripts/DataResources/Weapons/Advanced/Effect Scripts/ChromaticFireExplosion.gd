# File: res://Scripts/Weapons/Advanced/Effect Scripts/ChromaticFireExplosion.gd
# Attach to: ChromaticFireExplosion.tscn (Root Area2D)
# Purpose: Handles the damage and visual scaling for the fire proc.
# UPDATED: Duplicates its collision shape on ready to prevent sizing bugs with Cinderbloom.

class_name ChromaticFireExplosion
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready():
	# FIX: Duplicate the shape resource to make it unique to this instance.
	# This prevents the Cinderbloom upgrade from causing all explosions to resize.
	if is_instance_valid(collision_shape) and is_instance_valid(collision_shape.shape):
		collision_shape.shape = collision_shape.shape.duplicate()
		
	animated_sprite.animation_finished.connect(queue_free)

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	var damage_percent = float(p_stats.get("fire_explosion_damage_percentage", 2.5))
	var weapon_tags: Array[StringName] = p_stats.get("tags", [])
	
	if p_stats.get(&"has_intensify_flames", false):
		damage_percent *= 2.0
		
	var base_damage = p_player_stats.get_calculated_base_damage(damage_percent)
	var damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	
	var base_radius = float(p_stats.get("fire_explosion_radius", 70.0))
	var aoe_mult = p_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	var final_radius = base_radius * aoe_mult
	
	if p_stats.get(&"has_intensify_flames", false):
		final_radius *= 1.5

	(collision_shape.shape as CircleShape2D).radius = final_radius
	
	var sprite_texture = animated_sprite.sprite_frames.get_frame_texture("explode", 0)
	if is_instance_valid(sprite_texture):
		var texture_size = sprite_texture.get_width()
		if texture_size > 0:
			animated_sprite.scale = Vector2.ONE * (final_radius * 2 / texture_size)
			
	animated_sprite.play("explode")
	
	call_deferred("_deal_damage", damage, p_player_stats.get_parent(), weapon_tags)
	
	if p_stats.get(&"has_cinderbloom", false):
		var spawn_dist = float(p_stats.get("cinderbloom_spawn_distance", 80.0))
		call_deferred("_spawn_cinderbloom_explosions", p_stats, p_player_stats, spawn_dist)

func _deal_damage(damage: int, owner: Node, weapon_tags: Array[StringName]):
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		if body is BaseEnemy and not body.is_dead():
			body.take_damage(damage, owner, {}, weapon_tags)

func _spawn_cinderbloom_explosions(p_stats: Dictionary, p_player_stats: PlayerStats, spawn_dist: float):
	for i in range(2):
		var explosion = load("res://Scenes/Weapons/Advanced/Effect Scenes/ChromaticFireExplosion.tscn").instantiate()
		get_tree().current_scene.add_child(explosion)
		
		var random_offset = Vector2.RIGHT.rotated(randf_range(0, TAU)) * randf_range(spawn_dist * 0.5, spawn_dist)
		explosion.global_position = self.global_position + random_offset
		
		var cinder_stats = p_stats.duplicate(true)
		cinder_stats["fire_explosion_damage_percentage"] = float(p_stats.get("fire_explosion_damage_percentage", 2.5)) * 0.5
		cinder_stats["fire_explosion_radius"] = float(p_stats.get("fire_explosion_radius", 70.0)) * 0.6
		cinder_stats["has_cinderbloom"] = false # Prevent infinite loops
		
		if explosion.has_method("initialize"):
			explosion.initialize(cinder_stats, p_player_stats)
