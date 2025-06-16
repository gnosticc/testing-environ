# CrossbowAttackController.gd
# This script orchestrates the firing pattern of the Crossbow.
# It reads flags from its stats to determine if it should fire a single bolt,
# a triple-shot burst, or multiple bursts in succession (Ballista Barrage).

class_name CrossbowAttackController
extends Node2D

# Assign your CrossbowBolt.tscn scene to this variable in the Inspector.
@export var bolt_scene: PackedScene

# --- Internal State ---
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _base_direction: Vector2

func _ready():
	# The controller's logic is entirely driven by the set_attack_properties function.
	# It is designed to execute its firing pattern and then remove itself.
	pass

# This is the main entry point, called by WeaponManager.
func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	if not is_instance_valid(bolt_scene):
		push_error("CrossbowAttackController ERROR: Bolt Scene is not assigned! Aborting attack."); queue_free(); return
	
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_base_direction = direction

	# Determine the firing pattern based on flags.
	var has_triple_shot = _specific_stats.get(&"has_triple_shot", false)
	var has_ballista_barrage = _specific_stats.get(&"has_ballista_barrage", false)
	
	if has_ballista_barrage:
		# If we have Ballista Barrage, fire two bursts in succession.
		var delay = float(_specific_stats.get(&"ballista_barrage_delay", 0.2))
		_fire_burst(has_triple_shot)
		await get_tree().create_timer(delay).timeout
		if is_instance_valid(self): # Check if the node still exists after the delay
			_fire_burst(has_triple_shot)
	else:
		# Otherwise, fire a single burst.
		_fire_burst(has_triple_shot)
		
	# The controller's job is done, so it removes itself.
	queue_free()

# Fires a single "burst" of bolts. A burst is either one bolt or three (for Triple Shot).
func _fire_burst(is_triple_shot: bool):
	if is_triple_shot:
		# Fire three bolts in a cone spread.
		var spread_angle = deg_to_rad(15.0) # 15-degree spread on each side
		_spawn_bolt(_base_direction.rotated(-spread_angle)) # Left bolt
		_spawn_bolt(_base_direction) # Center bolt
		_spawn_bolt(_base_direction.rotated(spread_angle)) # Right bolt
	else:
		# Fire a single, standard bolt.
		_spawn_bolt(_base_direction)

# Instantiates and initializes a single crossbow bolt.
func _spawn_bolt(direction: Vector2):
	if not is_instance_valid(bolt_scene) or not is_instance_valid(_owner_player_stats): return

	var bolt_instance = bolt_scene.instantiate()
	var owner_player = _owner_player_stats.get_parent()

	# Add the bolt to the main attacks container to live independently.
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(bolt_instance)
	else:
		get_tree().current_scene.add_child(bolt_instance) # Fallback

	bolt_instance.global_position = owner_player.global_position
	
	# Pass all the necessary stats to the projectile instance.
	if bolt_instance.has_method("set_attack_properties"):
		bolt_instance.set_attack_properties(direction, _specific_stats, _owner_player_stats)
