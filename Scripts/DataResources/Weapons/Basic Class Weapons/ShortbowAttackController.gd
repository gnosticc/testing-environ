# ShortbowAttackController.gd
# This script manages the two-shot burst for the Shortbow.
# It fires one arrow left, waits, then fires another right.
#
# UPDATED: Uses PlayerStatKeys for standardized stat access.
# UPDATED: Ensures _received_stats is a deep copy to prevent unintended modifications.
# UPDATED: Uses push_error for consistent error reporting.

class_name ShortbowAttackController
extends Node2D

# In the Godot Inspector, drag your "ShortbowArrow.tscn" file into this slot.
@export var arrow_scene: PackedScene

var _received_stats: Dictionary # Stores the calculated weapon-specific stats from WeaponManager
var _owner_player_stats: PlayerStats # Reference to the player's PlayerStats node

# This function is called by the WeaponManager when the Shortbow attack is initiated.
# _direction: The base direction for the entire Shortbow attack sequence (unused for multi-directional fire).
# p_attack_stats: The weapon's specific_stats dictionary (these are the calculated stats from WeaponManager).
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	# Create a deep copy of the attack stats to ensure this instance has its own modifiable data.
	_received_stats = p_attack_stats.duplicate(true)
	_owner_player_stats = p_player_stats

	# Validate that the arrow scene is assigned.
	if not is_instance_valid(arrow_scene):
		push_error("ERROR (ShortbowAttackController): Arrow scene is not assigned. Cannot fire arrows!")
		queue_free() # Remove self if essential resource is missing
		return

	# Fire the first arrow immediately, directed to the left.
	_fire_arrow(Vector2.LEFT)

	# Set up a timer to fire the second arrow after a short delay.
	# The 'shot_delay' value is retrieved using PlayerStatKeys for consistency.
	var shot_delay = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.SHOT_DELAY], 0.1))
	var timer = get_tree().create_timer(shot_delay, true, false, true) # One-shot timer
	timer.timeout.connect(_fire_second_arrow)

# Fires an individual arrow instance in the specified direction.
# direction: The normalized direction vector for the arrow.
func _fire_arrow(direction: Vector2):
	# Safety check to ensure the arrow scene is still valid.
	if not is_instance_valid(arrow_scene): return

	var arrow_instance = arrow_scene.instantiate()
	
	# Determine the appropriate container for the projectile (e.g., "AttacksContainer").
	# This prevents projectiles from being children of the player and getting freed with the player.
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(arrow_instance)
	else:
		# Fallback: if the dedicated container is not found, add to the current scene's root.
		get_tree().current_scene.add_child(arrow_instance)

	# Position the arrow at the controller's (player's) global position.
	arrow_instance.global_position = self.global_position

	# Pass the arrow's properties, including direction, calculated weapon stats, and player stats.
	if arrow_instance.has_method("set_attack_properties"):
		arrow_instance.set_attack_properties(direction, _received_stats, _owner_player_stats)
	else:
		push_error("ERROR (ShortbowAttackController): Spawned arrow instance '", arrow_instance.name, "' is missing 'set_attack_properties' method.")

# Fires the second arrow of the burst and then queues the controller for removal.
func _fire_second_arrow():
	# Fire the second shot to the right.
	_fire_arrow(Vector2.RIGHT)
	
	# The controller's job is done after both arrows are fired, so it removes itself from the tree.
	queue_free()
