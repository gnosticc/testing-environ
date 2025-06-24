# File: res/Scripts/Effects/StatusVisualEffect.gd
# REVISED: Now accepts and applies a final scale multiplier for artistic control.

class_name StatusVisualEffect
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var target_enemy: BaseEnemy
var anchor_point: StatusEffectData.VisualAnchor = StatusEffectData.VisualAnchor.ABOVE
var scale_multiplier: float = 1.0 # The final tuning knob

func _ready():
	self.process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(animated_sprite):
		animated_sprite.animation_finished.connect(queue_free)
	if is_instance_valid(target_enemy):
		target_enemy.tree_exiting.connect(queue_free)

# MODIFIED: Initialize now accepts a scale multiplier.
func initialize(p_target_enemy: BaseEnemy, duration: float, p_anchor_point: StatusEffectData.VisualAnchor, p_scale_multiplier: float):
	if not is_instance_valid(p_target_enemy):
		queue_free(); return

	target_enemy = p_target_enemy
	anchor_point = p_anchor_point
	scale_multiplier = p_scale_multiplier
	
	_attach_and_position()
	
	animated_sprite.play("default")
	
	var lifetime_timer = Timer.new()
	lifetime_timer.one_shot = true
	lifetime_timer.wait_time = duration
	lifetime_timer.timeout.connect(queue_free)
	add_child(lifetime_timer)
	lifetime_timer.start()

func _attach_and_position():
	target_enemy.add_child(self)
	
	var y_offset = 0.0
	var enemy_sprite = target_enemy.get_node_or_null("AnimatedSprite2D")

	if is_instance_valid(enemy_sprite) and is_instance_valid(enemy_sprite.sprite_frames):
		var current_anim = enemy_sprite.animation
		var current_frame = enemy_sprite.frame
		if enemy_sprite.sprite_frames.has_animation(current_anim):
			var frame_texture = enemy_sprite.sprite_frames.get_frame_texture(current_anim, current_frame)
			if is_instance_valid(frame_texture):
				var enemy_root_scale = target_enemy.scale
				var sprite_node_scale = enemy_sprite.scale
				var texture_size = frame_texture.get_size()
				
				var enemy_visual_size = texture_size * sprite_node_scale * enemy_root_scale
				
				var effect_texture = animated_sprite.sprite_frames.get_frame_texture("default", 0)
				var effect_base_size = effect_texture.get_size()
				
				# --- SCALING LOGIC ---
				if effect_base_size.x > 0:
					# 1. Calculate the base scale factor to match the enemy's width.
					var base_scale_factor = enemy_visual_size.x / effect_base_size.x
					# 2. Apply the final data-driven multiplier.
					var final_scale = base_scale_factor * scale_multiplier
					animated_sprite.scale = Vector2.ONE * final_scale

				# --- ANCHORING LOGIC ---
				var enemy_visual_height = enemy_visual_size.y
				match anchor_point:
					StatusEffectData.VisualAnchor.ABOVE:
						y_offset = - (enemy_visual_height / 2.0) - 10 
					StatusEffectData.VisualAnchor.BELOW:
						y_offset = (enemy_visual_height / 2.0) + 10 
					StatusEffectData.VisualAnchor.CENTER:
						y_offset = 0

	if target_enemy.scale.y != 0:
		self.position = Vector2(0, y_offset / target_enemy.scale.y)
	else:
		self.position = Vector2.ZERO
