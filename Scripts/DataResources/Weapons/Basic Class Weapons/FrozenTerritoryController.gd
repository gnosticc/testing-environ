# FrozenTerritoryController.gd
# This script's only job is to spawn the correct number of orbiting instances
# with the correct spacing and stats, then remove itself.
# UPDATED: Uses PlayerStatKeys for stat lookups.

class_name FrozenTerritoryController
extends Node2D

@export var instance_scene: PackedScene

func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	if not is_instance_valid(instance_scene):
		push_error("ERROR (FrozenTerritoryController): Missing Instance Scene!"); queue_free(); return
	
	var owner_player = p_player_stats.get_parent() as PlayerCharacter # Cast for type safety
	if not is_instance_valid(owner_player):
		push_error("ERROR (FrozenTerritoryController): PlayerCharacter is invalid. Cannot spawn instances."); queue_free(); return
	
	# Use PlayerStatKeys for instance_count lookup
	var instance_count = int(p_attack_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.NUMBER_OF_ORBITS], 1))
	var angle_step = TAU / instance_count # TAU is 2*PI, a full circle

	for i in range(instance_count):
		var instance = instance_scene.instantiate() as FrozenTerritoryInstance
		
		# Add to a general container so it doesn't get destroyed with this controller
		var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
		if is_instance_valid(attacks_container):
			attacks_container.add_child(instance)
		else:
			get_tree().current_scene.add_child(instance)
			
		var start_angle = i * angle_step
		# Pass p_attack_stats directly, as these are the *calculated* weapon stats from WeaponManager
		instance.initialize(owner_player, p_attack_stats, start_angle)
		
	# This controller's job is done.
	queue_free()
