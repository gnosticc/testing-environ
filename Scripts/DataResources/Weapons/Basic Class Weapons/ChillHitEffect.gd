# File: res://Scripts/Weapons/Projectiles/ChillHitEffect.gd
# Purpose: Plays a single animation on an enemy upon damage, then frees itself.

class_name ChillHitEffect
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready():
	if not is_instance_valid(animated_sprite):
		push_error("ChillHitEffect ERROR: Missing AnimatedSprite2D child!")
		queue_free()
		return
	
	# Connect the animation finished signal to queue_free to remove the effect.
	animated_sprite.animation_finished.connect(queue_free)
	
	# Play the animation.
	animated_sprite.play("default") # Ensure this matches an animation in your SpriteFrames

# Function to set the scale of the animated sprite.
func set_effect_scale(scale_factor: float):
	if is_instance_valid(animated_sprite):
		animated_sprite.scale = Vector2(scale_factor, scale_factor)
	else:
		push_warning("ChillHitEffect: Attempted to set scale on invalid animated_sprite.")
