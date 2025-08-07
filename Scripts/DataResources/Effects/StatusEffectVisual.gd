# StatusEffectVisual.gd
# A generic script for visual effects tied to status effects.
# It handles positioning based on an anchor point, scaling, and self-destruction.
# VERSION 1.1: Renamed 'owner' to 'effect_owner' to avoid conflict with Node2D's built-in property.

class_name StatusEffectVisual extends Node2D

var effect_owner: Node2D # SOLUTION: Renamed from 'owner'
var duration: float

@onready var sprite: Sprite2D = $Sprite2D # Assumes a child Sprite2D node

# This function is called by the StatusEffectComponent
func initialize(p_owner: Node2D, p_duration: float, p_anchor_point: StatusEffectData.VisualAnchor, p_scale_multiplier: float):
	effect_owner = p_owner # SOLUTION: Renamed from 'owner'
	duration = p_duration
	
	# 1. Parent this visual effect to the owner so it moves with them.
	effect_owner.add_child(self)
	
	# 2. Get the owner's sprite to measure its size.
	var owner_sprite = effect_owner.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(owner_sprite) and owner_sprite.sprite_frames:
		var frame_texture = owner_sprite.sprite_frames.get_frame_texture(&"idle", 0)
		if frame_texture:
			var sprite_height = frame_texture.get_height()
			var final_visual_scale_y = effect_owner.scale.y * owner_sprite.scale.y
			
			# 3. Use the anchor point to determine the vertical position.
			match p_anchor_point:
				StatusEffectData.VisualAnchor.ABOVE:
					position.y = - (sprite_height / 2.0) * final_visual_scale_y - 15
				StatusEffectData.VisualAnchor.CENTER:
					position.y = 0
				StatusEffectData.VisualAnchor.BELOW:
					position.y = (sprite_height / 2.0) * final_visual_scale_y + 15
	
	# 4. Apply the scale multiplier from the data file.
	scale *= p_scale_multiplier

	# If the effect has a duration, create a timer to remove the visual when it expires.
	if duration > 0:
		var lifetime_timer = get_tree().create_timer(duration, false)
		lifetime_timer.timeout.connect(queue_free)
