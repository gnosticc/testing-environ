# LesserSpiritController.gd
# REVISED: Now emits a signal with the instances it creates, allowing
# the WeaponManager to track them for future stat updates.

class_name LesserSpiritController
extends Node2D

@export var instance_scene: PackedScene

# NEW: Signal to report spawned instances back to the WeaponManager.
signal instances_spawned(summon_id: StringName, spawned_instances: Array[Node2D])

func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	var received_stats_copy = p_attack_stats.duplicate(true)
	var owner_player = p_player_stats.get_parent() as PlayerCharacter
	var owner_player_stats = p_player_stats

	if not is_instance_valid(instance_scene):
		push_error("ERROR (LesserSpiritController): Instance Scene is not assigned! Queueing free."); queue_free(); return
	
	if not is_instance_valid(owner_player) or not is_instance_valid(owner_player_stats):
		push_error("ERROR (LesserSpiritController): Owner PlayerCharacter or PlayerStats is invalid! Queueing free."); queue_free(); return
	
	var base_instance_count = int(received_stats_copy.get(&"max_summons_of_type", 1))
	var global_summon_count_add = int(owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_COUNT_ADD))
	var final_instance_count = base_instance_count + global_summon_count_add
	
	var angle_step = TAU / float(final_instance_count)
	
	# NEW: Array to collect the references to the newly created spirits.
	var newly_spawned_spirits: Array[Node2D] = []

	for i in range(final_instance_count):
		var instance = instance_scene.instantiate()
		
		if not is_instance_valid(instance):
			push_error("ERROR (LesserSpiritController): Failed to instantiate LesserSpiritInstance scene for instance #", i, "!"); continue
		
		# The spirit instance should be a child of the main scene, not the player, to avoid rotation issues.
		get_tree().current_scene.add_child(instance)
		
		var start_angle = i * angle_step
		
		if instance.has_method("initialize"):
			(instance as LesserSpiritInstance).initialize(owner_player, received_stats_copy, start_angle)
			# Add the valid instance to our list for reporting.
			newly_spawned_spirits.append(instance)
		else:
			push_warning("LesserSpiritController: Spawned instance #", i, " is missing 'initialize' method.")

	# NEW: Emit the signal with the weapon's ID and the list of instances created.
	var weapon_id_for_tracking = received_stats_copy.get(&"weapon_id", &"conjurer_lesser_spirit")
	emit_signal("instances_spawned", weapon_id_for_tracking, newly_spawned_spirits)

	queue_free()
