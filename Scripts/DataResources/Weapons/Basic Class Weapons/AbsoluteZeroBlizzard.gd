# File: res://Scripts/Weapons/Projectiles/AbsoluteZeroBlizzard.gd
# MODIFIED: Logic added to scale the animation and set its transparency.

class_name AbsoluteZeroBlizzard
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var damage_tick_timer: Timer = $DamageTickTimer

var _damage_per_tick: int
var _slow_effect_data: StatusEffectData
var _owner_player_stats: PlayerStats
var _source_node: Node
var _weapon_stats: Dictionary # <-- FIX: Declare variable here

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	damage_tick_timer.timeout.connect(_on_damage_tick)
	body_entered.connect(_on_body_entered)

func initialize(p_player_stats: PlayerStats, p_source_node: Node, p_weapon_stats: Dictionary):
	_owner_player_stats = p_player_stats
	_source_node = p_source_node
	_weapon_stats = p_weapon_stats # <-- FIX: Assign to class variable
	
	_slow_effect_data = load("res://DataResources/StatusEffects/slow_status.tres")

	var radius = 200.0
	var duration = 1.0
	var damage_mult = 2.5
	
	if collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = radius
	
	var ft_blueprint = load("res://DataResources/Weapons/FrozenTerritory/wizard_frozen_territory_blueprint.tres") as WeaponBlueprintData
	var ft_damage_percent = ft_blueprint.initial_specific_stats.get(&"weapon_damage_percentage", 1.0)
	
	# --- REFACTORED DAMAGE CALCULATION ---
	var base_damage = _owner_player_stats.get_calculated_base_damage(ft_damage_percent)
	var base_orb_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, ft_blueprint.tags)
	# --- END REFACTOR ---

	_damage_per_tick = int(round(base_orb_damage * damage_mult))


	lifetime_timer.wait_time = duration
	lifetime_timer.start()
	damage_tick_timer.start()

	if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames.has_animation(&"default"):
		# --- NEW: Scale animation and set transparency ---
		# Get the base size of the animation sprite (assuming it's roughly square)
		var sprite_base_size = animated_sprite.sprite_frames.get_frame_texture(&"default", 0).get_width()
		
		if sprite_base_size > 0:
			# The desired diameter of the visual is twice the damage radius.
			var desired_diameter = radius * 2.0
			# The scale factor is the desired size divided by the base size.
			var scale_factor = desired_diameter / sprite_base_size
			animated_sprite.scale = Vector2(scale_factor, scale_factor)
		
		# Set the color to be semi-transparent
		animated_sprite.modulate = Color(1.0, 1.0, 1.0, 0.14) # 60% opacity
		
		animated_sprite.play("default")

func _on_damage_tick():
	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
			var weapon_tags: Array[StringName] = []
			if _weapon_stats.has("tags"):
				weapon_tags = _weapon_stats.get("tags")
			body.take_damage(_damage_per_tick, _source_node, {}, weapon_tags)

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
		if is_instance_valid(body.status_effect_component) and is_instance_valid(_slow_effect_data):
			body.status_effect_component.apply_effect(_slow_effect_data, _source_node, {}, -1.0, 0.5)
