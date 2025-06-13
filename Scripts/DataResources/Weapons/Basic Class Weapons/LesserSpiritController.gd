# LesserSpiritController.gd
# Spawns the correct number of persistent Lesser Spirit instances
# based on weapon stats, then removes itself.
#
# UPDATED: Passes weapon tags to the individual LesserSpiritInstance.
# UPDATED: Incorporates GLOBAL_SUMMON_COUNT_ADD from PlayerStats to determine total summon count.
# UPDATED: Uses push_error for consistent error reporting.
# ADDED: Debug prints to trace instantiation and parenting.
# NEW: Added 'instances_spawned' signal to report actual spawned LesserSpiritInstance nodes.

class_name LesserSpiritController
extends Node2D

@export var instance_scene: PackedScene

# New signal to report spawned instances to WeaponManager
signal instances_spawned(summon_id: StringName, spawned_instances: Array[Node2D])

# Standardized initialization function called by WeaponManager.
# _direction: The direction vector (unused for summon spawning, but kept for signature consistency).
# p_attack_stats: The weapon's specific_stats dictionary (these are the calculated stats from WeaponManager).
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	print("LesserSpiritController DEBUG: set_attack_properties called.")
	var received_stats_copy = p_attack_stats.duplicate(true) # Create a deep copy to ensure isolated data.
	var owner_player = p_player_stats.get_parent() as PlayerCharacter
	var owner_player_stats = p_player_stats # Direct reference to PlayerStats

	if not is_instance_valid(instance_scene):
		push_error("ERROR (LesserSpiritController): Instance Scene is not assigned or is invalid! Queueing free."); queue_free(); return
	
	if not is_instance_valid(owner_player) or not is_instance_valid(owner_player_stats):
		push_error("ERROR (LesserSpiritController): Owner PlayerCharacter or PlayerStats is invalid! Queueing free."); queue_free(); return
	
	# Calculate the final instance count, incorporating GLOBAL_SUMMON_COUNT_ADD
	var base_instance_count = int(received_stats_copy.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAX_SUMMONS_OF_TYPE], 1))
	var global_summon_count_add = int(owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_COUNT_ADD))
	var final_instance_count = base_instance_count + global_summon_count_add
	
	print("LesserSpiritController DEBUG: Spawning ", final_instance_count, " Lesser Spirit instances.")
	
	var angle_step = TAU / float(final_instance_count) # Distribute instances evenly in orbit
	
	var newly_spawned_spirits: Array[Node2D] = [] # Collect newly spawned spirits to report

	for i in range(final_instance_count):
		var instance = instance_scene.instantiate()
		
		if not is_instance_valid(instance):
			push_error("ERROR (LesserSpiritController): Failed to instantiate LesserSpiritInstance scene for instance #", i, "!"); continue
		
		owner_player.add_child(instance)
		print("LesserSpiritController DEBUG: Instance #", i, " instantiated and added as child of Player at path: ", instance.get_path())
		
		var start_angle = i * angle_step
		
		# Call initialize on the actual LesserSpiritInstance, passing it the full stats
		if instance.has_method("initialize"):
			(instance as LesserSpiritInstance).initialize(owner_player, received_stats_copy, start_angle)
			print("LesserSpiritController DEBUG: Instance #", i, " initialized.")
			newly_spawned_spirits.append(instance) # Add to list to report
		else:
			push_warning("LesserSpiritController: Spawned instance #", i, " is missing 'initialize' method. Not a LesserSpiritInstance?")

	# NEW: Emit signal with the spawned instances and the weapon ID (from blueprint)
	var weapon_id_for_tracking = received_stats_copy.get(&"weapon_id", &"lesser_spirit") # Assume WeaponManager provides 'weapon_id'
	emit_signal("instances_spawned", weapon_id_for_tracking, newly_spawned_spirits)
	print("LesserSpiritController DEBUG: Emitted instances_spawned signal for ", weapon_id_for_tracking)

	# This controller's job is done after spawning all instances.
	queue_free()
	print("LesserSpiritController DEBUG: Controller queued for free.")
