# File: res://Scripts/Effects/ChainBashVisual.gd
# REVISED: Now uses a timer for a fixed lifetime, making it more robust.

class_name ChainBashVisual
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func initialize(start_pos: Vector2, end_pos: Vector2):
	global_position = start_pos.lerp(end_pos, 0.5)
	rotation = (end_pos - start_pos).angle()

	if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames:
		var sprite_texture = animated_sprite.sprite_frames.get_frame_texture("default", 0)
		if is_instance_valid(sprite_texture):
			var base_width = sprite_texture.get_width()
			if base_width > 0:
				var distance = start_pos.distance_to(end_pos)
				animated_sprite.scale.x = distance / base_width
	
	# Use a timer to control its lifetime, which corresponds to the damage delay.
	var lifetime_timer = get_tree().create_timer(0.5)
	lifetime_timer.timeout.connect(queue_free)
	
	animated_sprite.play("default")
