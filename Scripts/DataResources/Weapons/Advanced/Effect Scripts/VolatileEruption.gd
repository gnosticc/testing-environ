# Path: res://Scripts/Weapons/Advanced/Effect Scenes/VolatileEruption.gd
# FIX: Correctly and safely initialize weapon_tags to prevent type mismatch errors.
# =====================================================================
class_name VolatileEruption
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready():
	pass

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	var base_radius = float(p_stats.get("magical_reaction_aoe_radius", 60.0))
	var aoe_mult = p_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	var final_radius = base_radius * aoe_mult
	var damage_mult = float(p_stats.get("magical_reaction_aoe_damage_mult", 1.4))
	var visual_scale = float(p_stats.get("magical_reaction_visual_scale", 1.0))
	
	if collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = final_radius
	
	animated_sprite.scale = Vector2.ONE * visual_scale
	animated_sprite.play("explode")

	var anim_duration = 0.6
	
	var tween = create_tween().set_parallel()
	var scale_tweener = tween.tween_property(animated_sprite, "scale", animated_sprite.scale * 1.2, anim_duration)
	scale_tweener.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var modulate_tweener = tween.tween_property(animated_sprite, "modulate:a", 0.0, anim_duration)
	modulate_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)
	
	await get_tree().physics_frame
	
	var all_hit_enemies: Array[BaseEnemy] = []
	for body in get_overlapping_bodies():
		if body is BaseEnemy and not body.is_dead():
			all_hit_enemies.append(body)

	var owner = p_player_stats.get_parent()

	var weapon_tags: Array[StringName] = []
	if p_stats.has("tags"):
		weapon_tags = p_stats.get("tags")

	# Step 1: Get the base damage.
	var base_damage = p_player_stats.get_calculated_base_damage(damage_mult)
	# Step 2: Apply tag-specific multipliers to get the final damage.
	var damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	for enemy in all_hit_enemies:
		enemy.take_damage(damage, owner, {}, weapon_tags)
		
		if p_stats.get("has_chain_reaction", false):
			if is_instance_valid(enemy.status_effect_component):
				var soaked_status = load("res://DataResources/StatusEffects/Alchemist/soaked_status.tres")
				enemy.status_effect_component.apply_effect(soaked_status, owner)
