# Path: res://Scripts/Weapons/Projectiles/EntangleEffect.gd
# Attach this script to the root node of your Entangle.tscn scene.
class_name EntangledEffect
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

# FIX: Changed the type of the third argument to 'int' to match the data being passed
# by the StatusEffectComponent, resolving the type mismatch error.
func initialize(p_owner: Node, p_duration: float, _p_anchor_point: int, _p_scale_multiplier: float):
	# Attach this visual effect to the enemy that was rooted.
	if is_instance_valid(p_owner):
		p_owner.add_child(self)
		self.global_position = p_owner.global_position
	
	animated_sprite.play("default") # Assuming your animation is named "default"
	
	# If the root status has a duration, make the visual effect last that long.
	if p_duration > 0:
		get_tree().create_timer(p_duration).timeout.connect(queue_free)
	else:
		# If the duration is -1 (permanent until removed), the StatusEffectComponent
		# will handle removing this visual effect when the owner is no longer rooted.
		# This is a fallback in case it's not cleaned up properly.
		get_tree().create_timer(10.0).timeout.connect(queue_free)
