# enemy_bat_fast.gd
# Script for the Slime Tall Light Blue enemy.
extends BaseEnemy

# Optional: If the bat has unique properties not covered by EnemyData
# @export var swoop_chance: float = 0.1 

func _ready():
	# Fallback stats (will be overridden by bat_fast_data.tres)
	# max_health = 15
	# contact_damage = 4
	# speed = 75.0 
	# experience_to_drop = 3
	# armor = 0

	super()
	
	# Bats use a "fly" animation instead of the default "move"
	#_play_animation("fly") # Assuming you have a "fly" animation in its SpriteFrames

# Override _physics_process for unique movement
# func _physics_process(delta: float):
#     if is_dead_flag: return
#     
#     # Custom bat movement logic here (e.g., erratic, swooping)
#     # For example, maybe it doesn't use separation force or has a different chase pattern.
#     # If you still want some base functionality like player tracking:
#     var direction_to_player = Vector2.ZERO
#     if is_instance_valid(player_node):
#         direction_to_player = (player_node.global_position - global_position).normalized()
#
#     # Example: Add some sideways oscillation to the movement
#     var sideways_movement = Vector2(sin(Time.get_ticks_msec() * 0.005), 0).rotated(direction_to_player.angle() + PI/2) * 0.3
#     var final_direction = (direction_to_player + sideways_movement).normalized()
#
#     var current_move_speed = speed # Apply status effects if needed as in BaseEnemy
#     velocity = final_direction * current_move_speed
#     
#     if is_instance_valid(animated_sprite):
#         if velocity.x < -0.01: animated_sprite.flip_h = true
#         elif velocity.x > 0.01: animated_sprite.flip_h = false
#     move_and_slide()


# func _on_swoop_timer_timeout(): # Example for a special ability
#     if randf() < swoop_chance:
#         # Perform swoop attack
#         pass
