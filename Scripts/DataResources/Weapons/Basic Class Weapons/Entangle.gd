# File: res://Scripts/Effects/Entangle.gd
# Attach this to the root Node2D of res://Scenes/Weapons/Projectiles/Entangle.tscn
# The scene should just contain an AnimatedSprite2D.
# REVISED: Scales effect 30% larger than the target and syncs its lifetime to the root duration.

class_name EntangleEffect
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var target_enemy: BaseEnemy

# Preload the status effect data to read its duration.
const ROOT_STATUS_DATA = preload("res://DataResources/StatusEffects/root_status.tres")

func _ready():
	# Set the process mode to ALWAYS so this visual effect is not affected
	# by get_tree().paused = true. This is critical for the lifetime timer.
	self.process_mode = Node.PROCESS_MODE_ALWAYS
	
	# If the target enemy is destroyed before the effect finishes, free this effect too.
	if is_instance_valid(target_enemy):
		target_enemy.tree_exiting.connect(queue_free)

func initialize(p_target_enemy: BaseEnemy):
	if not is_instance_valid(p_target_enemy):
		queue_free()
		return

	target_enemy = p_target_enemy
	
	# Parent this effect to the enemy so it moves with it.
	p_target_enemy.add_child(self)
	# Reset position to be centered on the new parent.
	self.position = Vector2.ZERO

	# Scale the effect to match the enemy's visual size.
	var enemy_sprite = target_enemy.get_node_or_null("AnimatedSprite2D")
	if is_instance_valid(enemy_sprite) and is_instance_valid(enemy_sprite.sprite_frames):
		var current_anim = enemy_sprite.animation
		var current_frame = enemy_sprite.frame
		if enemy_sprite.sprite_frames.has_animation(current_anim):
			var frame_texture = enemy_sprite.sprite_frames.get_frame_texture(current_anim, current_frame)
			if is_instance_valid(frame_texture):
				var enemy_size = frame_texture.get_size() * enemy_sprite.scale
				var effect_base_size = animated_sprite.sprite_frames.get_frame_texture("default", 0).get_size()
				
				if effect_base_size.x > 0 and effect_base_size.y > 0:
					var scale_x = enemy_size.x / effect_base_size.x
					var scale_y = enemy_size.y / effect_base_size.y
					var final_scale = min(scale_x, scale_y)
					
					# NEW: Increase the final calculated scale by 30%.
					animated_sprite.scale = (Vector2.ONE * final_scale) * 1.3

	# The animation should loop to look like a persistent effect.
	animated_sprite.animation_looped.connect(_on_animation_looped) # Use looped signal for safety
	animated_sprite.play("default") # Assuming the animation is named "default"
	
	# NEW: Create a timer to delete the effect after the root duration.
	var lifetime_timer = Timer.new()
	lifetime_timer.one_shot = true
	# Set the timer's duration from the preloaded status effect data.
	if is_instance_valid(ROOT_STATUS_DATA):
		lifetime_timer.wait_time = ROOT_STATUS_DATA.duration
	else:
		lifetime_timer.wait_time = 3.0 # Fallback to 3 seconds if data can't be loaded
	
	lifetime_timer.timeout.connect(queue_free)
	add_child(lifetime_timer)
	lifetime_timer.start()

# This is a failsafe in case the animation is accidentally not set to loop.
func _on_animation_looped():
	if not animated_sprite.is_playing():
		animated_sprite.play("default")
