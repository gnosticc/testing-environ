# Explosion.gd
# This script is attached to a simple Area2D scene. When created, it plays an
# animation, applies damage to all enemies within its radius once, and then
# removes itself after the animation finishes.
# CORRECTED: The explosion animation is now scaled to match the damage radius.
# FIX: Deferred setting of collision shape radius to prevent "flushing queries" error.

class_name Explosion
extends Area2D

# This should point to the AnimatedSprite2D node in your Explosion.tscn
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
var _specific_stats: Dictionary

func _ready():
	# Safety check to ensure the required nodes are present in the scene.
	if not is_instance_valid(animated_sprite) or not is_instance_valid(collision_shape):
		push_error("Explosion.gd ERROR: Scene is missing AnimatedSprite2D or CollisionShape2D. Destroying self.")
		queue_free()
		return
		
	# Connect the animation_finished signal to the queue_free function.
	# This ensures the explosion node is removed from the game only after its animation has completed.
	animated_sprite.animation_finished.connect(queue_free)

# This function is called by the node that creates the explosion (e.g., CrossbowBolt).
func detonate(damage_amount: int, radius: float, source_node: Node, attack_stats: Dictionary, _can_echo: bool = false, p_weapon_stats: Dictionary = {}):
	# Set the radius of the explosion's collision shape.
	if collision_shape.shape is CircleShape2D:
		# FIX: Use call_deferred to safely set the radius.
		# This prevents the "Can't change this state while flushing queries" error
		# by ensuring the modification happens at a safe time in the physics pipeline.
		(collision_shape.shape as CircleShape2D).call_deferred("set", &"radius", radius)
	else:
		push_error("Explosion.gd ERROR: CollisionShape2D does not have a CircleShape2D. Cannot set radius.")

	# Play the visual effect. Make sure you have an animation named "explosion"
	# in the SpriteFrames resource of your AnimatedSprite2D.
	if animated_sprite.sprite_frames.has_animation(&"explosion"):
		
		# --- NEW LOGIC: Scale the animation to match the radius ---
		# Get the base size of the animation sprite (assuming it's roughly square)
		var sprite_base_size = animated_sprite.sprite_frames.get_frame_texture(&"explosion", 0).get_width()
		
		if sprite_base_size > 0:
			# The desired diameter of the visual is twice the damage radius.
			var desired_diameter = radius * 2.0
			# The scale factor is the desired size divided by the base size.
			var scale_factor = desired_diameter / sprite_base_size
			animated_sprite.scale = Vector2(scale_factor, scale_factor)
		else:
			push_warning("Explosion.gd WARNING: Sprite base size is 0. Cannot scale animation.")

		animated_sprite.play("explosion")
	else:
		push_warning("Explosion.gd WARNING: 'explosion' animation not found. The effect will be invisible.")
		# If no animation, we still deal damage and then free it after a very short delay.
		get_tree().create_timer(0.1).timeout.connect(queue_free)

	# We must wait one physics frame to allow the engine to detect overlapping bodies.
	await get_tree().physics_frame
	
	# Get all enemy bodies currently inside the explosion's area.
	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			var enemy_target = body as BaseEnemy
			if is_instance_valid(enemy_target) and not enemy_target.is_dead():
				var weapon_tags: Array[StringName] = []
				if _specific_stats.has("tags"):
					weapon_tags = _specific_stats.get("tags")
				enemy_target.take_damage(damage_amount, source_node, attack_stats, weapon_tags)
