# WaveMovementBehavior.gd
# A component that modifies an enemy's movement to follow a sine wave pattern,
# creating an evasive "S"-shaped path towards its target.
# VERSION 1.1: Added a minimum range to disable weaving for final approach.

class_name WaveMovementBehavior extends Node

# --- Node References ---
var owner_enemy: BaseEnemy
var enemy_data: EnemyData
var player_node: PlayerCharacter

# --- Behavior Variables ---
var _time: float = 0.0 # A running timer to drive the sine wave

# --- Public API ---

func initialize(p_owner_enemy: BaseEnemy):
	owner_enemy = p_owner_enemy
	enemy_data = owner_enemy.enemy_data_resource
	player_node = owner_enemy.player_node
	# Randomize the starting time to prevent all wave enemies from moving in sync.
	_time = randf() * 100.0

func get_modified_velocity(delta: float, current_velocity: Vector2) -> Vector2:
	if not is_instance_valid(enemy_data) or not is_instance_valid(player_node):
		return current_velocity

	# --- SOLUTION: Disable weaving at close range ---
	var dist_sq_to_player = owner_enemy.global_position.distance_squared_to(player_node.global_position)
	if dist_sq_to_player < enemy_data.wave_disable_range * enemy_data.wave_disable_range:
		return current_velocity # Return the original velocity to move straight.
	# --- END SOLUTION ---

	_time += delta
	
	# Get the properties from the data file.
	var amplitude = enemy_data.wave_amplitude
	var frequency = enemy_data.wave_frequency
	
	# Calculate the sine wave offset.
	var offset = sin(_time * frequency) * amplitude
	
	# Get the direction perpendicular to the current movement.
	var perpendicular_direction = current_velocity.orthogonal().normalized()
	
	# Add the offset to the original velocity.
	return current_velocity + (perpendicular_direction * offset)
