# --- Path: res://Scripts/Weapons/Advanced/LivingConduitController.gd ---
class_name LivingConduitController
extends Node2D

const LIGHTNING_BOLT_SCENE = preload("res://Scenes/Weapons/Advanced/LightningBolt.tscn")

func set_attack_properties(_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	var num_bolts = int(p_stats.get(&"initial_bolt_count", 1))
	var owner_player = p_player_stats.get_parent()
	
	# FIX: Call the correct, newly created function.
	var targets = owner_player._find_nearest_enemies(num_bolts)
	
	# Add a safety check in case no targets are found.
	if targets.is_empty():
		queue_free()
		return
	
	for target in targets:
		if is_instance_valid(target):
			var bolt = LIGHTNING_BOLT_SCENE.instantiate()
			get_tree().current_scene.add_child(bolt)
			bolt.strike(target, p_stats, p_player_stats)
	
	queue_free()
