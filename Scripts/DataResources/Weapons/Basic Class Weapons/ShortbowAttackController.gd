# ShortbowAttackController.gd
# This script manages the two-shot burst for the Shortbow.
# It fires one arrow left, waits, then fires another right.
class_name ShortbowAttackController
extends Node2D

# In the Godot Inspector, drag your "ShortbowArrowAttack.tscn" file into this slot.
@export var arrow_scene: PackedScene

var _received_stats: Dictionary
var _owner_player_stats: PlayerStats

# This function is called by the WeaponManager
func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	_received_stats = p_attack_stats
	_owner_player_stats = p_player_stats

	if not is_instance_valid(arrow_scene):
		print("ERROR: Shortbow controller has no arrow scene assigned!")
		queue_free()
		return

	# Fire the first shot immediately to the left
	_fire_arrow(Vector2.LEFT)

	# Set up a timer to fire the second shot
	var shot_delay = float(_received_stats.get("shot_delay", 0.1))
	var timer = get_tree().create_timer(shot_delay, true, false, true)
	timer.timeout.connect(_fire_second_arrow)

func _fire_arrow(direction: Vector2):
	if not is_instance_valid(arrow_scene): return

	var arrow_instance = arrow_scene.instantiate()
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	
	if is_instance_valid(attacks_container):
		attacks_container.add_child(arrow_instance)
	else:
		# Fallback if the container isn't found
		get_tree().current_scene.add_child(arrow_instance)

	# The controller itself is spawned at the player's position
	arrow_instance.global_position = self.global_position

	if arrow_instance.has_method("set_attack_properties"):
		arrow_instance.set_attack_properties(direction, _received_stats, _owner_player_stats)

func _fire_second_arrow():
	# Fire the second shot to the right
	_fire_arrow(Vector2.RIGHT)
	# The controller's job is done, so it removes itself.
	queue_free()
