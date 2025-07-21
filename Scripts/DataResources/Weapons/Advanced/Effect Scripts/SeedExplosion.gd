# --- Path: res://Scripts/Weapons/Advanced/Effects/SeedExplosion.gd ---
class_name SeedExplosion
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# Member variables to store data from initialize
var _damage: int
var _source_player: PlayerCharacter
var _specific_stats: Dictionary

func _ready():
	animated_sprite.animation_finished.connect(queue_free)

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	# Store the stats and player reference as member variables
	_specific_stats = p_stats
	_source_player = p_player_stats.get_parent()

	var aoe_mult = p_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	var radius = float(p_stats.get(&"seed_explosion_radius", 40.0)) * aoe_mult
	var damage_percent = float(p_stats.get(&"seed_explosion_damage_percentage", 1.2))
	
	# Store the calculated damage as a member variable
	var weapon_tags: Array[StringName] = p_stats.get("tags", [])
	var base_damage = p_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage = final_damage	
	
	if collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = radius
	
	var sprite_texture = animated_sprite.sprite_frames.get_frame_texture("explode", 0)
	if is_instance_valid(sprite_texture):
		var texture_size = sprite_texture.get_width()
		var desired_diameter = radius * 2
		if texture_size > 0:
			animated_sprite.scale = Vector2.ONE * (desired_diameter / texture_size)
	
	animated_sprite.play("explode")
	
	# The timer now calls _deal_damage directly, without binding arguments.
	get_tree().create_timer(0.02, false).timeout.connect(_deal_damage)

func _deal_damage():
	if not is_instance_valid(self): return
	monitoring = true
	await get_tree().physics_frame
	
	# CORRECTED: Initialize as a typed array first, then assign.
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")

	for body in get_overlapping_bodies():
		if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
			# Use the member variables to call take_damage with all required arguments.
			body.take_damage(_damage, _source_player, {}, weapon_tags)
			
	monitoring = false
