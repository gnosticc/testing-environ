# File: res://Scripts/Weapons/Advanced/Effect Scripts/ChromaticNaturePool.gd
# Attach to: ChromaticNaturePool.tscn (Root Area2D)
# Purpose: Handles the damage-over-time and debuffing for the nature proc.
# UPDATED: Duplicates its collision shape on ready to prevent sizing bugs with Viscous Splatter.

class_name ChromaticNaturePool
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var damage_tick_timer: Timer = $DamageTickTimer

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _damage_per_tick: int
var _armor_break_status: StatusEffectData

func _ready():
	# FIX: Duplicate the shape resource to make it unique to this instance.
	# This prevents the Viscous Splatter upgrade from causing all pools to resize.
	if is_instance_valid(collision_shape) and is_instance_valid(collision_shape.shape):
		collision_shape.shape = collision_shape.shape.duplicate()

	lifetime_timer.timeout.connect(queue_free)
	damage_tick_timer.timeout.connect(_on_damage_tick)
	body_entered.connect(_on_body_entered)
	animated_sprite.play("active")

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	
	var damage_percent = float(p_stats.get("nature_pool_damage_percentage", 0.5))
	var weapon_tags: Array[StringName] = p_stats.get("tags", [])
	var base_damage = p_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage_per_tick = final_damage
	
	var base_radius = float(p_stats.get("nature_pool_radius", 60.0))
	var aoe_mult = p_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	var final_radius = base_radius * aoe_mult
	
	if p_stats.get(&"has_corrosive_sap", false):
		final_radius *= 1.25
	
	(collision_shape.shape as CircleShape2D).radius = final_radius
	
	var sprite_texture = animated_sprite.sprite_frames.get_frame_texture("active", 0)
	if is_instance_valid(sprite_texture):
		var texture_size = sprite_texture.get_width()
		if texture_size > 0:
			animated_sprite.scale = Vector2.ONE * (final_radius * 2 / texture_size)
			
	var duration = float(p_stats.get("nature_pool_duration", 3.0))
	if p_stats.get(&"has_wild_growth", false): # This key is from the old design, but harmless to leave for now
		duration += 2.0
	
	lifetime_timer.wait_time = duration
	lifetime_timer.start()
	damage_tick_timer.start()
	
	if p_stats.get(&"has_viscous_splatter", false):
		var min_dist = float(p_stats.get("viscous_splatter_min_distance", 40.0))
		var max_dist = float(p_stats.get("viscous_splatter_distance", 100.0))
		call_deferred("_spawn_splatter_pools", p_stats, p_player_stats, min_dist, max_dist)

func _on_damage_tick():
	await get_tree().physics_frame
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	for body in get_overlapping_bodies():
		if body is BaseEnemy and not body.is_dead():
			body.take_damage(_damage_per_tick, _owner_player_stats.get_parent(), {}, weapon_tags)

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not body.is_dead():
		if _specific_stats.get(&"has_corrosive_sap", false):
			if not is_instance_valid(_armor_break_status):
				_armor_break_status = load("res://DataResources/StatusEffects/armor_break_status.tres")
			if is_instance_valid(body.status_effect_component):
				var potency = -10.0 # The armor reduction value
				body.status_effect_component.apply_effect(_armor_break_status, _owner_player_stats.get_parent(), {}, 5.0, potency)

func _spawn_splatter_pools(p_stats: Dictionary, p_player_stats: PlayerStats, min_dist: float, max_dist: float):
	for i in range(3):
		var pool = load("res://Scenes/Weapons/Advanced/Effect Scenes/ChromaticNaturePool.tscn").instantiate()
		get_tree().current_scene.add_child(pool)
		
		var random_offset = Vector2.RIGHT.rotated(randf_range(0, TAU)) * randf_range(min_dist, max_dist)
		pool.global_position = self.global_position + random_offset
		
		var splatter_stats = p_stats.duplicate(true)
		splatter_stats["nature_pool_radius"] = float(p_stats.get("nature_pool_radius", 60.0)) * 0.5
		splatter_stats["has_viscous_splatter"] = false # Prevent infinite loops
		
		if pool.has_method("initialize"):
			pool.initialize(splatter_stats, p_player_stats)
