# File: Scripts/Weapons/Advanced/CataclysmHitEffect.gd
# MODIFIED: Re-implemented initialize() function to scale based on the
# target's CollisionShape2D instead of its visual sprite.

class_name CataclysmHitEffect
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready():
	# This setup is excellent and requires no changes.
	self.process_mode = Node.PROCESS_MODE_ALWAYS
	
	if not is_instance_valid(animated_sprite):
		queue_free(); return
		
	animated_sprite.animation_finished.connect(queue_free)

	# Failsafe timer is a great practice.
	get_tree().create_timer(0.5, true, false, true).timeout.connect(queue_free)

	animated_sprite.play("impact")


# This function is called by WarhammerController to set up the ON-HIT effect on an enemy.
func initialize(target_enemy: BaseEnemy):
	# Fail gracefully if the target is invalid.
	if not is_instance_valid(target_enemy):
		return
		
	# Ensure the effect renders on top of the enemy.
	self.z_index = target_enemy.z_index + 1
	
	# --- PRECISE SCALING LOGIC ---
	var enemy_collision_shape = target_enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
	
	if is_instance_valid(enemy_collision_shape) and is_instance_valid(enemy_collision_shape.shape):
		var shape_resource = enemy_collision_shape.shape
		var base_shape_width: float = 0.0

		# Determine the width from the shape's resource properties.
		if shape_resource is CapsuleShape2D:
			base_shape_width = shape_resource.radius * 2.0
		elif shape_resource is CircleShape2D:
			base_shape_width = shape_resource.radius * 2.0
		elif shape_resource is RectangleShape2D:
			base_shape_width = shape_resource.size.x
		
		if base_shape_width > 0:
			# This is the final, on-screen visual width of the enemy's collider.
			# This calculation is correct as it accounts for all parent scales.
			var target_collider_visual_width = base_shape_width * enemy_collision_shape.global_scale.x
			
			# Get the effect's own base texture.
			var effect_texture = animated_sprite.sprite_frames.get_frame_texture("impact", 0)
			if is_instance_valid(effect_texture):
				# IMPORTANT FIX: Calculate the effect's own visual width by including its sprite's local scale.
				# This was the likely source of the "too small" issue.
				var effect_base_visual_width = float(effect_texture.get_width()) * animated_sprite.scale.x
				
				if effect_base_visual_width > 0:
					# The required scale for this effect node is the ratio of the two visual widths.
					var required_scale = target_collider_visual_width / effect_base_visual_width
					self.scale = Vector2.ONE * required_scale
					return # Exit after successful scaling

	# --- FALLBACK SCALING ---
	push_warning("CataclysmHitEffect: Could not process CollisionShape2D on enemy. Using fallback scaling.")
	self.scale = target_enemy.global_scale
