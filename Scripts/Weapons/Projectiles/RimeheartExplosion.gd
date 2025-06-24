# File: res://Scripts/Weapons/Projectiles/RimeheartExplosion.gd
# MODIFIED: Logic moved into _ready() for stability. 'detonate_visual' removed.
# Added a setup function to receive data before being added to the scene.

class_name RimeheartExplosion
extends Area2D

# The visual sprite will be this much smaller than the actual damage radius.
const VISUAL_TO_HITBOX_RATIO = 0.75

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# Public variable to be set by the creator.
var radius: float = 35.0 # Default value

# This function is called by RimeheartAura to configure the explosion.
func setup_visual(p_radius: float):
	radius = p_radius

func _ready():
	monitoring = false
	if not is_instance_valid(animated_sprite) or not is_instance_valid(collision_shape):
		queue_free()
		return
	# Make sure the animation is not looping, or this signal will never fire.
	animated_sprite.animation_finished.connect(queue_free)

	# --- Logic now runs safely in _ready ---
	print_debug("RimeheartExplosion: Detonating visual with radius: ", radius)
	
	if collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = radius
	else:
		push_warning("RimeheartExplosion: CollisionShape2D is not a CircleShape2D.")
		
	var visual_radius = radius * VISUAL_TO_HITBOX_RATIO

	var sprite_base_size = animated_sprite.sprite_frames.get_frame_texture(&"default", 0).get_width()
	if sprite_base_size > 0:
		var visual_diameter = visual_radius * 2.0
		var scale_factor = visual_diameter / sprite_base_size
		animated_sprite.scale = Vector2(scale_factor, scale_factor)

	animated_sprite.play("default")
