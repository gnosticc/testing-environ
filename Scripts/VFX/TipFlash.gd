# File: res://Scripts/Effects/TipFlash.gd
# Attach this to the root Node2D of TipFlash.tscn
# FIX: Relies solely on animated_sprite.animation_finished for deletion.
# FIX: Ensures initialization logic is run, allowing self-deletion.

class_name TipFlash
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
# Removed: var lifetime_timer: Timer # No longer needed, relying on animation_finished

func _ready():
	# Set the process mode to ALWAYS so this visual effect is not affected
	# by get_tree().paused = true. This is critical for effects in paused scenes.
	self.process_mode = Node.PROCESS_MODE_ALWAYS
	
	if not is_instance_valid(animated_sprite) or not animated_sprite.sprite_frames:
		push_warning("TipFlash: Cannot initialize, sprite or sprite_frames invalid. Queueing free.")
		queue_free()
		return

	# Connect the animated_sprite's animation_finished signal to the node's self-destruction.
	# This is the most reliable way for a non-looping animation to trigger deletion.
	animated_sprite.animation_finished.connect(queue_free)
	
	# Play the animation immediately when the node is ready and added to the tree.
	var anim_name = "flash"
	if animated_sprite.sprite_frames.has_animation(anim_name):
		animated_sprite.play(anim_name)
	else:
		push_warning("TipFlash: SpriteFrames is missing the 'flash' animation. Queueing free.")
		# If animation doesn't exist, free quickly as there's nothing to play.
		queue_free()


# This function is called by the creating script to set up and run the effect.
# fixed_diameter: The desired fixed visual diameter for the flash effect.
func initialize(fixed_diameter: float):
	if not is_instance_valid(animated_sprite) or not animated_sprite.sprite_frames:
		return # Already handled in _ready(), or node will be freed.

	var anim_name = "flash"
	# No need to check has_animation again, _ready() already handled it.
	
	# Get the base size of the animation sprite for scaling.
	var base_size = 0.0
	if animated_sprite.sprite_frames.has_animation(anim_name):
		var first_frame_texture = animated_sprite.sprite_frames.get_frame_texture(anim_name, 0)
		if is_instance_valid(first_frame_texture):
			base_size = float(first_frame_texture.get_width())

	if base_size > 0:
		var scale_factor = fixed_diameter / base_size
		animated_sprite.scale = Vector2.ONE * scale_factor
	else:
		push_warning("TipFlash: Sprite base size is 0 or animation frame missing. Cannot scale effect.")

	# animated_sprite.play(anim_name) is already in _ready(), no need to call again unless resetting.
	# The self-deletion is now solely managed by the animation_finished signal.
