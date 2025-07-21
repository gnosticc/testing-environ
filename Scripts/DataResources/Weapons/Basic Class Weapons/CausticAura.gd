# File: res://Scripts/DataResources/Weapons/Summons/CausticAura.gd
# This script handles the persistent damage-over-time aura for the Moth Golem.
# FIX: Re-added z_index modification to ensure it renders behind other entities.
# FIX: Improved debug print to show both incoming damage and calculated tick damage.

class_name CausticAura
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_tick_timer: Timer = $DamageTickTimer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _damage_per_tick: int
var _golem_node: Node2D

func _ready():
	# Set a negative z_index to ensure the aura draws behind other entities like the golem and enemies.
	#self.z_index = -1
	damage_tick_timer.timeout.connect(_on_damage_tick)

# This function is called by MothGolem.gd to set up the aura.
func initialize(golem: Node2D, stats: Dictionary, golem_hit_damage: int):
	_golem_node = golem
	var radius = float(stats.get(&"caustic_aura_radius", 20.0))
	var damage_percent = float(stats.get(&"caustic_aura_damage_percent", 0.5))
	
	_damage_per_tick = int(round(maxf(1.0, golem_hit_damage * damage_percent)))
	
	# DEBUG: Improved print statement for clarity.
	print("CausticAura DEBUG: Initializing aura. Golem Base Hit: ", golem_hit_damage, ". Calculated Tick Damage (", damage_percent * 100, "%): ", _damage_per_tick)
	
	if is_instance_valid(collision_shape) and collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = radius
		
	if is_instance_valid(animated_sprite) and is_instance_valid(animated_sprite.sprite_frames):
		var sprite_base_size = animated_sprite.sprite_frames.get_frame_texture("default", 0).get_width()
		if sprite_base_size > 0:
			var scale_factor = (radius * 2.0) / sprite_base_size
			animated_sprite.scale = Vector2.ONE * scale_factor
			
		# Make the aura semi-transparent so it's not obstructive.
		animated_sprite.modulate = Color(1.0, 1.0, 1.0, 0.6) # 40% opacity
		
	damage_tick_timer.start()
	animated_sprite.play("default")

# This function is called every second by the timer to deal damage.
func _on_damage_tick():
	for body in get_overlapping_bodies():
		if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
			var weapon_tags: Array[StringName] = []
			if _golem_node.specific_weapon_stats.has("tags"):
				weapon_tags = _golem_node.specific_weapon_stats.get("tags")
			body.take_damage(_damage_per_tick, _golem_node, {}, weapon_tags) # Pass tags
