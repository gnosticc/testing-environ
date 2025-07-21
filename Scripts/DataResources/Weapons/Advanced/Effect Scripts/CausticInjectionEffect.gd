# File: res://Scripts/DataResources/Weapons/Advanced/Effect Scenes/CausticInjectionEffect.gd
# NEW SCRIPT
# This script controls the visual effect for the Caustic Injection status.
# It plays a dripping acid animation on the affected enemy.

class_name CausticInjectionEffect
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready():
	# Ensure the node is always processed, even if the game is paused (e.g., level-up screen)
	self.process_mode = Node.PROCESS_MODE_ALWAYS
	
	if not is_instance_valid(animated_sprite):
		push_error("CausticInjectionEffect ERROR: Missing AnimatedSprite2D child!")
		queue_free()
		return
	
	# The animation itself is set to not loop, so it will automatically free the scene when it finishes.
	animated_sprite.animation_finished.connect(queue_free)

# This function is called by the StatusEffectComponent when the effect is applied.
func initialize(p_owner: Node, p_duration: float, p_anchor_point: int, p_scale_multiplier: float):
	if not is_instance_valid(p_owner):
		queue_free()
		return

	# Attach this visual effect to the enemy that was affected.
	p_owner.add_child(self)
	self.position = Vector2.ZERO # Center on owner

	# Start the animation.
	animated_sprite.play("drip")

	# Failsafe timer to ensure the effect is removed if the animation signal fails for any reason.
	if p_duration > 0:
		get_tree().create_timer(p_duration + 0.5, true, false, true).timeout.connect(queue_free)
