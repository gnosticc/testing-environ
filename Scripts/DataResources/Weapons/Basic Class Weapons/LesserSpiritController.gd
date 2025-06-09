# LesserSpiritController.gd
# Spawns the correct number of persistent Lesser Spirit instances
# based on weapon stats, then removes itself.
class_name LesserSpiritController
extends Node2D

@export var instance_scene: PackedScene

func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	if not is_instance_valid(instance_scene):
		print("ERROR: LesserSpiritController is missing its Instance Scene!"); queue_free(); return
	
	var owner_player = p_player_stats.get_parent()
	if not is_instance_valid(owner_player):
		queue_free(); return
	
	var instance_count = int(p_attack_stats.get("max_summons_of_type", 1))
	var angle_step = TAU / instance_count

	for i in range(instance_count):
		var instance = instance_scene.instantiate() as LesserSpiritInstance
		
		# Summons are parented to the player so they are cleaned up if the player is.
		owner_player.add_child(instance)
		
		var start_angle = i * angle_step
		instance.initialize(owner_player, p_attack_stats, start_angle)
		
	# This controller's job is done.
	queue_free()
